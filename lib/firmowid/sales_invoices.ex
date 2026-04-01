defmodule Firmowid.SalesInvoices do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Ash.Billing
  alias Firmowid.Nbp
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.SalesInvoice

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

  @spec get_sales_invoice(UUIDv7.t()) :: SalesInvoice.t() | nil
  def get_sales_invoice(id) do
    SalesInvoice
    |> Repo.get(id)
    |> Repo.preload([
      :sales_invoice_items,
      :transactions,
      corrections: :sales_invoice_items,
      corrected_invoice: :corrections
    ])
  end

  def get_sales_invoice!(id) do
    SalesInvoice
    |> Repo.get!(id)
    |> Repo.preload([
      :sales_invoice_items,
      :transactions,
      corrections: :sales_invoice_items,
      corrected_invoice: :corrections
    ])
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
        {:ok,
         %{
           num: String.to_integer(num),
           month: String.to_integer(month),
           year: String.to_integer(year),
           series: nil
         }}

      [_, num, month, year, series] ->
        {:ok,
         %{
           num: String.to_integer(num),
           month: String.to_integer(month),
           year: String.to_integer(year),
           series: series
         }}

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
      adjust_billing_counter(created_invoice.organization_id, :sales_invoices, :increment_counter)
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
  def create_correction_invoice(
        %SalesInvoice{ksef_invoice_kind: :vat} = original_invoice,
        attrs,
        reference_invoice \\ nil
      ) do
    reference_invoice = reference_invoice || get_latest_invoice_snapshot(original_invoice)

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
  def cancel_sales_invoice(%SalesInvoice{ksef_invoice_kind: :vat} = original_invoice) do
    if SalesInvoice.ksef_submitted?(original_invoice) do
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

      create_correction_invoice(original_invoice, attrs, latest_snapshot)
    else
      {:error, :not_ksef_submitted}
    end
  end

  def get_latest_invoice_snapshot(%SalesInvoice{ksef_invoice_kind: :vat} = original_invoice) do
    original_invoice = Repo.preload(original_invoice, :corrections)

    original_invoice.corrections
    |> Enum.max_by(
      fn correction -> correction.locked_at || correction.inserted_at end,
      DateTime,
      fn -> original_invoice end
    )
    |> Repo.preload(:sales_invoice_items)
  end

  # commented out becase ci doesn't pass
  # @deprecated "Use populate_reference_invoices/1 instead"
  def get_reference_invoice(%SalesInvoice{ksef_invoice_kind: :kor} = invoice),
    do: populate_reference_invoices(invoice).reference_invoice

  def get_reference_invoice(%SalesInvoice{ksef_invoice_kind: :vat}), do: nil

  def populate_reference_invoices(%SalesInvoice{ksef_invoice_kind: :vat} = invoice) do
    invoice = Repo.preload(invoice, corrections: :sales_invoice_items)

    corrections = Enum.sort_by(invoice.corrections, &(&1.locked_at || &1.inserted_at), DateTime)
    references = [invoice | corrections]

    corrections =
      [corrections, references]
      |> Enum.zip()
      |> Enum.map(fn {correction, reference} ->
        %{correction | reference_invoice: reference, corrected_invoice: invoice}
      end)

    %{invoice | corrections: corrections}
  end

  def populate_reference_invoices(%SalesInvoice{ksef_invoice_kind: :kor} = invoice) do
    invoice = Repo.preload(invoice, corrected_invoice: :corrections)
    original_invoice = populate_reference_invoices(invoice.corrected_invoice)

    reference_invoice =
      original_invoice.corrections
      |> Enum.reject(fn correction ->
        correction.id == invoice.id or
          DateTime.after?(
            correction.locked_at || correction.inserted_at,
            invoice.locked_at || invoice.inserted_at
          )
      end)
      |> Enum.max_by(&(&1.locked_at || &1.inserted_at), DateTime, fn -> original_invoice end)
      |> Repo.preload(:sales_invoice_items)

    %{invoice | reference_invoice: reference_invoice, corrected_invoice: original_invoice}
  end

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
      with {:ok, deleted} <- result, do: maybe_decrement_billing(deleted)
      result
    else
      {:error, :ksef_submitted}
    end
  end

  defp maybe_decrement_billing(%SalesInvoice{} = invoice) do
    if correction_invoice?(invoice), do: :ok, else: do_decrement_billing(invoice)
  end

  defp do_decrement_billing(invoice) do
    adjust_billing_counter(invoice.organization_id, :sales_invoices, :decrement_counter)
  end

  defp correction_invoice?(%SalesInvoice{ksef_invoice_kind: :kor}), do: true
  defp correction_invoice?(_), do: false

  @token_bytes 32
  @spec create_or_get_share_token(SalesInvoice.t()) ::
          {:ok, SalesInvoice.t()} | {:error, Ecto.Changeset.t()}
  def create_or_get_share_token(%SalesInvoice{share_token: token} = invoice) when is_binary(token) and token != "" do
    {:ok, invoice}
  end

  def create_or_get_share_token(%SalesInvoice{ksef_invoice_kind: :vat} = invoice) do
    token = generate_share_token()

    invoice
    |> Ecto.Changeset.change(share_token: token)
    |> Repo.update()
  end

  @spec get_invoice_by_share_token(String.t()) :: {:ok, SalesInvoice.t()} | {:error, :not_found}
  def get_invoice_by_share_token(token) when is_binary(token) do
    invoice =
      case String.split(token, ".", parts: 2) do
        [share_token] ->
          Repo.get_by(SalesInvoice, [share_token: share_token], skip_organization_id: true)

        [share_token, correction_id] ->
          SalesInvoice
          |> where([i], i.id == ^correction_id and i.ksef_invoice_kind == :kor)
          |> join(:inner, [i], o in SalesInvoice, on: o.share_token == ^share_token)
          |> Repo.one(skip_organization_id: true)
      end

    invoice =
      Repo.preload(
        invoice,
        [
          :organization,
          :sales_invoice_items,
          :transactions,
          corrections: :sales_invoice_items,
          corrected_invoice: :corrections
        ],
        skip_organization_id: true
      )

    case invoice do
      nil -> {:error, :not_found}
      invoice -> {:ok, invoice}
    end
  end

  defp generate_share_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp adjust_billing_counter(organization_id, type, action) do
    billing_opts = [tenant: organization_id, authorize?: false, actor: %{}]

    with {:ok, limits} <- Billing.get_limits(billing_opts),
         {:ok, _} <- apply(Billing, action, [limits, %{type: type}, billing_opts]) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to #{action} #{type} billing limit: #{inspect(reason)}")
    end
  end
end
