defmodule Firmowid.SalesInvoices do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false
  import Paradex, only: [~>: 2]

  alias Ecto.Multi
  alias Firmowid.Accounts
  alias Firmowid.Billing
  alias Firmowid.Nbp
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoicesTransactions

  require Logger

  def authorize(:read_sales_invoice, %{role: :admin}, _), do: true
  def authorize(:create_sales_invoice, %{role: :admin}, _), do: true

  def authorize(action, %{role: :admin, organization_id: org_id}, %{organization_id: org_id})
      when action in [:show, :update, :delete, :cancel], do: true

  def authorize(_, _, _), do: false

  @sales_invoice_broadcast_topic "sales_invoice_broadcast_topic"

  def subscribe_sales_invoice_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@sales_invoice_broadcast_topic}:#{organization_id}"
    )
  end

  def broadcast_sales_invoice_list_updated(organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@sales_invoice_broadcast_topic}:#{organization_id}",
      :sales_invoice_list_updated
    )
  end

  def populate_logo_url(%SalesInvoice{} = sales_invoice) do
    loaded_invoice = Repo.preload(sales_invoice, :organization, skip_organization_id: true)
    organization = Accounts.get_organization_with_avatar(loaded_invoice.organization)
    %{loaded_invoice | logo_url: organization.avatar_url}
  end

  def populate_logo_url(nil), do: nil

  @doc """
  Returns the currency exchange rate for a sales invoice.

  For PLN invoices, returns nil (no conversion needed).
  For other currencies, fetches the NBP exchange rate for the currency conversion date.
  """
  @spec get_currency_rate(SalesInvoice.t()) :: map() | nil
  def get_currency_rate(%SalesInvoice{currency: "PLN"}), do: nil

  def get_currency_rate(%SalesInvoice{} = sales_invoice) do
    Nbp.ApiClient.get_exchange_rate(
      sales_invoice.currency,
      SalesInvoice.get_currency_conversion_date(sales_invoice)
    )
  end

  @doc """
  Returns the name for display purposes on an invoice.

  Priority:
  1. buyer_display_name (if set) - user's preferred short name
  2. For companies: buyer_full_name (legal name)
  3. For individuals: "buyer_given_name buyer_surname"

  Uses map pattern matching to be compatible with LiveView assigns
  which may add internal fields like :__given__.
  """
  @spec buyer_display_name(SalesInvoice.t() | map()) :: String.t() | nil
  def buyer_display_name(%{__struct__: SalesInvoice, buyer_display_name: name}) when is_binary(name) and name != "" do
    name
  end

  def buyer_display_name(%{__struct__: SalesInvoice, buyer_type: :company, buyer_full_name: name}) when is_binary(name) do
    name
  end

  def buyer_display_name(%{
        __struct__: SalesInvoice,
        buyer_type: :individual,
        buyer_given_name: given_name,
        buyer_surname: surname
      })
      when is_binary(given_name) and is_binary(surname) do
    "#{given_name} #{surname}"
  end

  def buyer_display_name(_), do: nil

  def search_sales_invoices(search_term) do
    SalesInvoice
    |> where(
      [i],
      ilike(i.invoice_number, ^"%#{search_term}%") or
        ilike(i.buyer_full_name, ^"%#{search_term}%") or
        ilike(i.buyer_given_name, ^"%#{search_term}%") or
        ilike(i.buyer_display_name, ^"%#{search_term}%") or
        ilike(i.buyer_surname, ^"%#{search_term}%") or
        ilike(i.buyer_address, ^"%#{search_term}%") or
        ilike(i.buyer_id, ^"%#{search_term}%") or
        ilike(i.buyer_pesel, ^"%#{search_term}%")
    )
    |> join(:left, [i], items in assoc(i, :sales_invoice_items))
    |> group_by([i], i.id)
    |> having([i, items], count(items.id) > 0)
    |> limit(15)
    |> order_by(desc: :updated_at)
    |> Repo.all()
    |> Repo.preload(:sales_invoice_items)
  end

  @doc """
  Unmatched invoices - due in a given date range, but
  without a match and not skipped.
  """
  def list_unmatched_sales_invoices do
    list_unmatched_sales_invoices(~D[1970-01-01], ~D[2999-12-31])
  end

  def list_unmatched_sales_invoices(from, to) do
    query =
      from si in SalesInvoice,
        left_join: sit in assoc(si, :transactions),
        where: si.ksef_invoice_kind == :vat,
        where: is_nil(sit.id),
        where: si.due_date >= ^from,
        where: si.due_date <= ^to,
        where: si.skip_invoicing == false,
        order_by: [desc: :issue_date]

    list_sales_invoices(query)
  end

  def list_sales_invoices(from, to) do
    SalesInvoice
    |> where(
      [d],
      d.issue_date >= ^from and d.issue_date <= ^to
    )
    |> order_by(desc: :issue_date)
    |> list_sales_invoices()
  end

  @doc """
  Lists sales invoices whose sale falls within the given date range.
  Used by the analysis dashboard so invoices appear in the month they were sold.
  """
  @spec list_sales_invoices_by_sale_date(Date.t(), Date.t()) :: [SalesInvoice.t()]
  def list_sales_invoices_by_sale_date(from, to) do
    SalesInvoice
    |> where([d], d.sale_date >= ^from and d.sale_date <= ^to)
    |> order_by(desc: :sale_date)
    |> list_sales_invoices()
  end

  def list_sales_invoices(base_query \\ SalesInvoice) do
    latest_corrections_query =
      from(c in SalesInvoice,
        where: c.ksef_invoice_kind == :kor,
        distinct: [asc: c.corrected_invoice_id],
        order_by: [asc: c.corrected_invoice_id, desc: c.locked_at, desc: c.inserted_at],
        preload: [:sales_invoice_items]
      )

    sales_invoices =
      base_query
      |> where([si], si.ksef_invoice_kind == :vat)
      |> preload([:sales_invoice_items, :transactions, corrections: ^latest_corrections_query])
      |> Repo.all()

    snapshot_fields = [
      :invoice_type,
      :sale_date,
      :due_date,
      :payment_method,
      :currency,
      :seller_nip,
      :seller_display_name,
      :seller_address,
      :seller_name,
      :seller_surname,
      :seller_account_number,
      :buyer_type,
      :buyer_id,
      :buyer_full_name,
      :buyer_given_name,
      :buyer_surname,
      :buyer_pesel,
      :buyer_display_name,
      :buyer_address,
      :buyer_country,
      :buyer_is_different_mail_address,
      :buyer_mail_address,
      :buyer_mail_country,
      :buyer_email,
      :buyer_phone,
      :buyer_description,
      :is_cash_account,
      :is_reverse_charge,
      :sales_invoice_items
    ]

    Enum.map(sales_invoices, fn
      %{corrections: []} = invoice ->
        invoice

      # we handle only one correction case, because we preload only latest correction
      %{corrections: [correction]} = invoice ->
        Map.merge(invoice, Map.take(correction, snapshot_fields))
    end)
  end

  def list_invoices_in_date_range(from, to) do
    SalesInvoice
    |> where(
      [d],
      (d.issue_date >= ^from and d.issue_date <= ^to) or
        (d.sale_date >= ^from and d.sale_date <= ^to)
    )
    |> order_by(desc: :issue_date)
    |> Repo.all()
  end

  @spec get_sales_invoice(UUIDv7.t()) :: SalesInvoice.t() | nil
  def get_sales_invoice(id) do
    SalesInvoice
    |> Repo.get(id)
    |> Repo.preload([:sales_invoice_items, :transactions, :corrections, corrected_invoice: :corrections])
  end

  def get_sales_invoice!(id) do
    SalesInvoice
    |> Repo.get!(id)
    |> Repo.preload([:sales_invoice_items, :transactions, :corrections, corrected_invoice: :corrections])
  end

  def get_sales_invoice_with_logo_url(id) do
    SalesInvoice
    |> Repo.get(id)
    |> Repo.preload([:sales_invoice_items, :transactions, :corrections, corrected_invoice: :corrections])
    |> populate_logo_url()
  end

  def create_sales_invoices_transactions_connection(invoice_ids, transaction_ids, organization_id) do
    invoice_ids =
      if is_list(invoice_ids) do
        invoice_ids
      else
        [invoice_ids]
      end

    transaction_ids =
      if is_list(transaction_ids) do
        transaction_ids
      else
        [transaction_ids]
      end

    changesets =
      for invoice_id <- invoice_ids, transaction_id <- transaction_ids do
        SalesInvoicesTransactions.changeset(%{
          sales_invoice_id: invoice_id,
          transaction_id: transaction_id,
          organization_id: organization_id
        })
      end

    changesets
    |> Enum.reduce(Multi.new(), fn %{changes: data} = changeset, acc ->
      Multi.insert(acc, {data.sales_invoice_id, data.transaction_id}, changeset)
    end)
    |> Repo.transaction()
  end

  def delete_sales_invoices_transactions_connections(invoice_id) do
    query = where(from(SalesInvoicesTransactions), [c], c.sales_invoice_id == ^invoice_id)

    Repo.delete_all(query)
  end

  def toggle_skip_invoicing(id) do
    sales_invoice = get_sales_invoice(id)

    sales_invoice =
      sales_invoice
      |> SalesInvoice.skip_invoicing_changeset(%{skip_invoicing: !sales_invoice.skip_invoicing})
      |> Repo.update!()

    broadcast_sales_invoice_list_updated(sales_invoice.organization_id)

    sales_invoice
  end

  def get_latest_sales_invoice do
    SalesInvoice
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:sales_invoice_items)
    |> populate_logo_url()
  end

  # Invoice Number Series Support
  # Format: NN/MM/YYYY (default) or NN/MM/YYYY/SERIES (with postfix)

  @invoice_number_regex ~r/^(\d+)\/(\d+)\/(\d+)(?:\/(.+))?$/

  @doc """
  Parses an invoice number string into its components.

  Returns `{:ok, %{num: integer, month: integer, year: integer, series: string | nil}}`
  for valid formats, or `:error` for invalid formats.

  ## Examples

      iex> parse_invoice_number("01/01/2026")
      {:ok, %{num: 1, month: 1, year: 2026, series: nil}}

      iex> parse_invoice_number("12/01/2026/A")
      {:ok, %{num: 12, month: 1, year: 2026, series: "A"}}

      iex> parse_invoice_number("EVIL/2025/11/001")
      :error
  """
  @spec parse_invoice_number(String.t()) ::
          {:ok, %{num: integer(), month: integer(), year: integer(), series: String.t() | nil}} | :error
  def parse_invoice_number(invoice_number) when is_binary(invoice_number) do
    case Regex.run(@invoice_number_regex, invoice_number) do
      [_, num, month, year] ->
        {:ok, %{num: String.to_integer(num), month: String.to_integer(month), year: String.to_integer(year), series: nil}}

      [_, num, month, year, series] ->
        {:ok,
         %{num: String.to_integer(num), month: String.to_integer(month), year: String.to_integer(year), series: series}}

      nil ->
        :error
    end
  end

  def parse_invoice_number(_), do: :error

  @doc """
  Formats invoice number components into a string.

  ## Examples

      iex> format_invoice_number(1, 1, 2026, nil)
      "01/01/2026"

      iex> format_invoice_number(12, 1, 2026, "A")
      "12/01/2026/A"
  """
  @spec format_invoice_number(integer(), integer(), integer(), String.t() | nil) :: String.t()
  def format_invoice_number(num, month, year, nil) do
    "#{String.pad_leading("#{num}", 2, "0")}/#{String.pad_leading("#{month}", 2, "0")}/#{year}"
  end

  def format_invoice_number(num, month, year, series) do
    "#{String.pad_leading("#{num}", 2, "0")}/#{String.pad_leading("#{month}", 2, "0")}/#{year}/#{series}"
  end

  @doc """
  Returns a list of distinct invoice number series used by the organization.

  Only includes series from invoice numbers matching the valid format (NN/MM/YYYY or NN/MM/YYYY/SERIES).
  Legacy formats like "EVIL/2025/11/001" are ignored.

  Returns `nil` as the first element representing the default (no postfix) series,
  followed by any named series in alphabetical order.
  """
  @spec list_invoice_series() :: [String.t() | nil]
  def list_invoice_series do
    SalesInvoice
    |> where([i], not is_nil(i.invoice_number))
    |> select([i], i.invoice_number)
    |> Repo.all()
    |> Enum.map(&parse_invoice_number/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, %{series: s}} -> s end)
    |> Enum.uniq()
    |> Enum.sort_by(fn
      nil -> ""
      s -> s
    end)
  end

  @doc """
  Returns the next available invoice number for the given date and series.

  ## Options

    * `:series` - The invoice series (postfix). `nil` for default series. Default: `nil`
    * `:omit_invoice_id` - Invoice ID to exclude from checks (for editing). Default: `nil`

  ## Examples

      iex> get_next_invoice_number(~D[2026-01-15])
      "04/01/2026"

      iex> get_next_invoice_number(~D[2026-01-15], series: "A")
      "12/01/2026/A"
  """
  @spec get_next_invoice_number(Date.t(), keyword()) :: String.t()
  def get_next_invoice_number(date, opts \\ []) do
    year = date.year
    month = date.month
    series = Keyword.get(opts, :series, nil)
    omit_invoice_id = Keyword.get(opts, :omit_invoice_id, nil)

    # Build pattern to match invoice numbers for this series
    # For nil series: "NN/MM/YYYY" (no trailing slash or postfix)
    # For named series: "NN/MM/YYYY/SERIES"
    series_pattern = build_series_pattern(month, year, series)

    # Get all invoice numbers matching this series pattern
    query =
      SalesInvoice
      |> where([i], not is_nil(i.invoice_number))
      |> where([i], fragment("? ~ ?", i.invoice_number, ^series_pattern))

    query =
      if omit_invoice_id do
        where(query, [i], i.id != ^omit_invoice_id)
      else
        query
      end

    # Find the highest number in this series
    existing_numbers =
      query
      |> select([i], i.invoice_number)
      |> Repo.all()
      |> Enum.map(&parse_invoice_number/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, %{num: num}} -> num end)

    starting_num =
      case Enum.max(existing_numbers, fn -> 0 end) do
        0 -> 1
        max_num -> max_num + 1
      end

    # Keep checking until we find a free number
    find_free_invoice_number(starting_num, month, year, series, omit_invoice_id)
  end

  # Build regex pattern for matching invoice numbers of a specific series
  defp build_series_pattern(month, year, nil) do
    # Match "NN/MM/YYYY" exactly (no trailing content)
    month_str = String.pad_leading("#{month}", 2, "0")
    "^\\d+/#{month_str}/#{year}$"
  end

  defp build_series_pattern(month, year, series) do
    # Match "NN/MM/YYYY/SERIES" exactly
    month_str = String.pad_leading("#{month}", 2, "0")
    # Escape special regex characters in series
    escaped_series = Regex.escape(series)
    "^\\d+/#{month_str}/#{year}/#{escaped_series}$"
  end

  defp find_free_invoice_number(num, month, year, series, omit_invoice_id) do
    # Format the invoice number using the helper
    invoice_number = format_invoice_number(num, month, year, series)

    # Check if this number already exists in the database
    query = where(SalesInvoice, [i], i.invoice_number == ^invoice_number)

    query =
      if omit_invoice_id do
        where(query, [i], i.id != ^omit_invoice_id)
      else
        query
      end

    if Repo.exists?(query) do
      # Number is taken, try the next one
      find_free_invoice_number(num + 1, month, year, series, omit_invoice_id)
    else
      # Number is free, return it
      invoice_number
    end
  end

  @doc """
  Returns a map of series to their next available invoice number.

  Always includes `nil` (default series) and `"A"` series, plus any existing series from the database.

  ## Examples

      iex> get_next_numbers_for_series(~D[2026-01-15])
      %{nil => "04/01/2026", "A" => "01/01/2026/A", "FIZ" => "03/01/2026/FIZ"}
  """
  @spec get_next_numbers_for_series(Date.t(), keyword()) :: %{(String.t() | nil) => String.t()}
  def get_next_numbers_for_series(date, opts \\ []) do
    existing_series = list_invoice_series()

    # Always include nil (default) and "A"
    all_series = Enum.uniq([nil, "A"] ++ existing_series)

    Map.new(all_series, fn series ->
      {series, get_next_invoice_number(date, Keyword.put(opts, :series, series))}
    end)
  end

  @typedoc """
  Invoice number validation warning.

  - `{:invalid_format, suggestions}` - Number doesn't match expected format
  - `{:duplicate, suggestions}` - Number already exists in database
  - `{:gap, expected}` - Number creates a gap in the sequence
  """
  @type invoice_warning ::
          {:invalid_format, [String.t()]}
          | {:duplicate, [String.t()]}
          | {:gap, String.t()}

  @doc """
  Validates an invoice number and returns a list of warnings.

  Checks for:
  - Invalid format (doesn't match NN/MM/YYYY or NN/MM/YYYY/SERIES)
  - Duplicate (number already exists)
  - Gap in sequence (number is higher than expected for the series)

  Each warning includes suggested corrections.

  ## Examples

      iex> validate_invoice_number("04/01/2026", ~D[2026-01-15])
      []

      iex> validate_invoice_number("INVALID", ~D[2026-01-15])
      [{:invalid_format, ["04/01/2026", "01/01/2026/A"]}]

      iex> validate_invoice_number("10/01/2026", ~D[2026-01-15])
      [{:gap, "04/01/2026"}]
  """
  @spec validate_invoice_number(String.t(), Date.t(), keyword()) :: [invoice_warning()]
  def validate_invoice_number(invoice_number, issue_date, opts \\ []) do
    all_suggestions =
      issue_date
      |> get_next_numbers_for_series(opts)
      |> Map.values()
      |> Enum.sort_by(fn num -> if String.contains?(num, "/A"), do: 1, else: 0 end)

    parsed = parse_invoice_number(invoice_number)

    warnings = []

    # Check format
    warnings =
      if parsed == :error do
        [{:invalid_format, all_suggestions} | warnings]
      else
        warnings
      end

    # Check duplicate
    warnings =
      if invoice_number_exists?(invoice_number, opts) do
        [{:duplicate, all_suggestions} | warnings]
      else
        warnings
      end

    # Check gap (only if format is valid)
    warnings =
      case parsed do
        {:ok, %{num: current_num, series: series}} ->
          expected = get_next_invoice_number(issue_date, Keyword.put(opts, :series, series))

          case parse_invoice_number(expected) do
            {:ok, %{num: expected_num}} when current_num > expected_num ->
              [{:gap, expected} | warnings]

            _ ->
              warnings
          end

        :error ->
          warnings
      end

    Enum.reverse(warnings)
  end

  defp invoice_number_exists?(invoice_number, opts) do
    omit_invoice_id = Keyword.get(opts, :omit_invoice_id)
    query = where(SalesInvoice, [i], i.invoice_number == ^invoice_number)

    query =
      if omit_invoice_id do
        where(query, [i], i.id != ^omit_invoice_id)
      else
        query
      end

    Repo.exists?(query)
  end

  @doc """
  Creates a new sales invoice.

  Note: The billing counter increment happens outside the insert transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful invoice creation over counter accuracy.
  If the increment fails, a warning is logged but the invoice is still created.
  Counter drift is acceptable for soft limit tracking.
  """
  def create_sales_invoice(%SalesInvoice{} = invoice, attrs) do
    result =
      invoice
      |> SalesInvoice.changeset(attrs)
      |> Repo.insert()

    with {:ok, created_invoice} <- result do
      case Billing.increment(created_invoice.organization_id, :sales_invoices) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to increment sales_invoices limit: #{inspect(reason)}")
      end
    end

    result
  end

  @doc """
  Creates a correction invoice (KOR) for an existing invoice.

  The original invoice must be:
  - Submitted to KSeF (has ksef_number)
  - Locked (has locked_at)

  Seller and buyer data are automatically copied from the original invoice.
  """
  def create_correction_invoice(%SalesInvoice{ksef_invoice_kind: :vat} = original_invoice, attrs) do
    original_invoice = Repo.preload(original_invoice, [:sales_invoice_items, corrections: :sales_invoice_items])

    reference_invoice = get_latest_invoice_snapshot(original_invoice)

    original_invoice
    |> SalesInvoice.prepare_correction_invoice_changeset(reference_invoice)
    |> SalesInvoice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Cancels a KSeF-submitted VAT invoice by creating a correction invoice (KOR)
  that zeros out all line items.

  Cancellation is only allowed from the latest invoice snapshot in a correction
  chain (same rule as editing). The corrected (original) invoice must be a locked,
  KSeF-submitted VAT invoice.
  """
  @spec cancel_sales_invoice(SalesInvoice.t()) :: {:ok, SalesInvoice.t()} | {:error, Ecto.Changeset.t()}
  def cancel_sales_invoice(%SalesInvoice{} = invoice) do
    invoice =
      Repo.preload(invoice, [
        :sales_invoice_items,
        :corrections,
        corrected_invoice: [:sales_invoice_items, corrections: :sales_invoice_items]
      ])

    original_invoice = if invoice.ksef_invoice_kind == :kor, do: invoice.corrected_invoice, else: invoice

    if SalesInvoice.locked?(original_invoice) do
      latest_snapshot = get_latest_invoice_snapshot(original_invoice)

      issue_date = Date.utc_today()
      invoice_number = get_next_invoice_number(issue_date, series: "FK")

      zeroed_items_attrs =
        Enum.map(latest_snapshot.sales_invoice_items, fn item ->
          item
          |> Map.take([:index, :name, :unit, :unit_price, :vat_rate])
          |> Map.put(:quantity, Decimal.new(0))
        end)

      correction_reason =
        case latest_snapshot.invoice_type do
          :foreign -> "Anulowanie faktury / Invoice cancellation"
          _poland -> "Anulowanie faktury"
        end

      attrs = %{
        invoice_number: invoice_number,
        issue_date: issue_date,
        sale_date: latest_snapshot.sale_date,
        due_date: latest_snapshot.due_date,
        correction_reason: correction_reason,
        sales_invoice_items: zeroed_items_attrs
      }

      original_invoice
      |> SalesInvoice.prepare_correction_invoice_changeset(latest_snapshot)
      |> SalesInvoice.changeset(attrs)
      |> Repo.insert()
    else
      {:error, :not_ksef_submitted}
    end
  end

  def get_latest_invoice_snapshot(%SalesInvoice{ksef_invoice_kind: :vat} = original_invoice) do
    latest_correction =
      original_invoice.corrections
      |> Enum.reject(&is_nil(&1.locked_at))
      |> Enum.max_by(& &1.locked_at, DateTime, fn -> nil end)

    latest_correction || original_invoice
  end

  def get_reference_invoice_for_correction(%SalesInvoice{ksef_invoice_kind: :kor} = correction_invoice) do
    correction_invoice =
      Repo.preload(correction_invoice, corrected_invoice: :corrections)

    original_invoice = correction_invoice.corrected_invoice

    # Only consider locked (submitted) corrections as potential references.
    # Unlocked corrections haven't been submitted yet and can't be referenced.
    locked_corrections =
      Enum.reject(original_invoice.corrections, &is_nil(&1.locked_at))

    reference_invoice =
      cond do
        Enum.empty?(locked_corrections) ->
          original_invoice

        is_nil(correction_invoice.locked_at) ->
          # Current correction is not locked yet — reference is the latest locked correction
          Enum.max_by(locked_corrections, & &1.locked_at, DateTime)

        true ->
          # Current correction is locked — reference is the latest correction locked before it
          locked_corrections
          |> Enum.filter(&DateTime.before?(&1.locked_at, correction_invoice.locked_at))
          |> Enum.max_by(& &1.locked_at, DateTime, fn -> original_invoice end)
      end

    Repo.preload(reference_invoice, :sales_invoice_items)
  end

  def get_reference_invoice_for_correction(%SalesInvoice{ksef_invoice_kind: :vat}) do
    raise "Reference invoice is only applicable for KOR invoices"
  end

  @spec get_reference_invoice(SalesInvoice.t()) :: SalesInvoice.t() | nil
  def get_reference_invoice(%SalesInvoice{ksef_invoice_kind: :kor} = invoice) do
    get_reference_invoice_for_correction(invoice)
  end

  def get_reference_invoice(%SalesInvoice{}), do: nil

  def update_sales_invoice(%SalesInvoice{} = invoice, attrs) do
    invoice
    |> SalesInvoice.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a sales invoice.

  Returns `{:error, :ksef_submitted}` if the invoice has been submitted to KSeF
  or is currently locked for submission. KSeF-submitted invoices cannot be deleted
  and must be cancelled via correction invoice instead.

  Note: The billing counter decrement happens outside the delete transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful invoice deletion over counter accuracy.
  If the decrement fails, a warning is logged but the invoice is still deleted.
  Counter drift is acceptable for soft limit tracking.
  """
  def delete_sales_invoice(%SalesInvoice{} = invoice) do
    if SalesInvoice.deletable?(invoice) do
      result = Repo.delete(invoice)

      with {:ok, deleted_invoice} <- result do
        if !correction_invoice?(deleted_invoice) do
          case Billing.decrement(deleted_invoice.organization_id, :sales_invoices) do
            {:ok, _} -> :ok
            {:error, reason} -> Logger.warning("Failed to decrement sales_invoices limit: #{inspect(reason)}")
          end
        end
      end

      result
    else
      {:error, :ksef_submitted}
    end
  end

  defp correction_invoice?(%SalesInvoice{ksef_invoice_kind: :kor}), do: true
  defp correction_invoice?(_), do: false

  def list_sales_invoices_by_ids(ids, date_from \\ nil, date_to \\ nil) do
    query =
      SalesInvoice
      |> where([si], si.id in ^ids)
      |> where([si], si.ksef_invoice_kind == :vat)

    query =
      if date_from do
        where(query, [si], si.issue_date >= ^date_from)
      else
        query
      end

    query =
      if date_to do
        where(query, [si], si.issue_date <= ^date_to)
      else
        query
      end

    query
    |> order_by(desc: :issue_date)
    |> list_sales_invoices()
  end

  @doc """
  Lists recent invoices from the previous two full months.

  For example, if today is 2026-02-03, this returns all confirmed invoices
  with `issue_date` in January 2026 or December 2025.

  Results are sorted by `issue_date` descending, then `invoice_number` descending.
  """
  def list_recent_invoices do
    today = Date.utc_today()
    range_end = %{today | day: 1}
    range_start = Date.shift(range_end, month: -2)

    SalesInvoice
    |> where([s], not is_nil(s.invoice_number))
    |> where([s], s.issue_date >= ^range_start and s.issue_date < ^range_end)
    |> order_by([s], desc: s.issue_date, desc: s.invoice_number)
    |> list_sales_invoices()
  end

  def list_counterparties do
    Counterparty
    |> order_by([c], asc: fragment("COALESCE(?, ?)", c.display_name, c.surname))
    |> Repo.all()
  end

  @spec get_counterparty(UUIDv7.t()) :: Counterparty.t() | nil
  def get_counterparty(id) do
    Repo.get(Counterparty, id)
  end

  @spec get_counterparty!(UUIDv7.t()) :: Counterparty.t()
  def get_counterparty!(id) do
    Repo.get!(Counterparty, id)
  end

  @spec create_counterparty(map()) :: {:ok, Counterparty.t()} | {:error, Ecto.Changeset.t()}
  def create_counterparty(attrs) do
    %Counterparty{}
    |> Counterparty.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_counterparty(Counterparty.t(), map()) ::
          {:ok, Counterparty.t()} | {:error, Ecto.Changeset.t()}
  def update_counterparty(%Counterparty{} = counterparty, attrs) do
    counterparty
    |> Counterparty.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_counterparty(Counterparty.t()) :: {:ok, Counterparty.t()} | {:error, Ecto.Changeset.t()}
  def delete_counterparty(%Counterparty{} = counterparty) do
    Repo.delete(counterparty)
  end

  def change_counterparty(%Counterparty{} = counterparty, attrs \\ %{}) do
    Counterparty.changeset(counterparty, attrs)
  end

  @spec search_counterparties(String.t(), keyword()) :: [Counterparty.t()]
  def search_counterparties(search_term, opts \\ []) do
    type = Keyword.get(opts, :type)
    sort_by = Keyword.get(opts, :sort_by, :name)
    sort_order = Keyword.get(opts, :sort_order, :asc)

    {search_mode, base_query} = apply_counterparty_search(Counterparty, search_term)

    base_query
    |> apply_counterparty_type_filter(type)
    |> apply_counterparty_sorting(search_mode, sort_by, sort_order)
    |> limit(25)
    |> Repo.all(prepare: :unnamed)
  end

  defp apply_counterparty_search(query, nil), do: {:no_search, query}
  defp apply_counterparty_search(query, ""), do: {:no_search, query}

  defp apply_counterparty_search(query, search_term) do
    search_query =
      where(
        query,
        [c],
        c.display_name ~> ^search_term or
          c.full_name ~> ^search_term or
          c.given_name ~> ^search_term or
          c.surname ~> ^search_term or
          c.tax_id ~> ^search_term or
          c.email ~> ^search_term
      )

    {:search, search_query}
  end

  defp apply_counterparty_type_filter(query, nil), do: query

  defp apply_counterparty_type_filter(query, type) when type in [:individual, :company] do
    where(query, [c], c.type == ^type)
  end

  defp apply_counterparty_type_filter(query, _), do: query

  # When searching, order by BM25 score first
  defp apply_counterparty_sorting(query, :search, _sort_by, _order) do
    order_by(query, [c], fragment("paradedb.score(?) DESC", c.id))
  end

  # When not searching, use the existing sorting logic
  # For individuals: given_name is set, full_name is NULL
  # For companies: full_name is set, given_name is NULL
  defp apply_counterparty_sorting(query, :no_search, :name, order) do
    order_by(query, [c], [{^order, fragment("COALESCE(?, ?)", c.given_name, c.full_name)}])
  end

  defp apply_counterparty_sorting(query, :no_search, :display_name, order) do
    order_by(query, [c], [{^order, fragment("COALESCE(?, ?)", c.full_name, c.given_name)}])
  end

  defp apply_counterparty_sorting(query, :no_search, :created_at, order) do
    order_by(query, [c], [{^order, c.inserted_at}])
  end

  defp apply_counterparty_sorting(query, :no_search, _, order) do
    # Default to name sorting
    apply_counterparty_sorting(query, :no_search, :name, order)
  end

  @token_bytes 32
  @spec create_or_get_share_token(SalesInvoice.t()) ::
          {:ok, SalesInvoice.t()} | {:error, Ecto.Changeset.t()}
  def create_or_get_share_token(%SalesInvoice{share_token: token} = invoice) when is_binary(token) and token != "" do
    {:ok, invoice}
  end

  def create_or_get_share_token(%SalesInvoice{} = invoice) do
    token = generate_share_token()

    invoice
    |> Ecto.Changeset.change(share_token: token)
    |> Repo.update()
  end

  @spec get_invoice_by_share_token(String.t()) :: {:ok, SalesInvoice.t()} | {:error, :not_found}
  def get_invoice_by_share_token(token) when is_binary(token) do
    case Repo.get_by(SalesInvoice, [share_token: token], skip_organization_id: true) do
      nil ->
        {:error, :not_found}

      invoice ->
        invoice =
          Repo.preload(
            invoice,
            [:organization, :sales_invoice_items, :transactions, :corrections, corrected_invoice: :corrections],
            skip_organization_id: true
          )

        {:ok, invoice}
    end
  end

  defp generate_share_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
