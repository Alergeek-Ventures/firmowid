defmodule Firmowid.Ash.Invoicing.SalesInvoice do
  @moduledoc """
  Ash resource for sales invoices.

  Read-only in this slice — mutations remain in the legacy `SalesInvoices` Ecto
  context until Slice 7.

  ## Actions

    * `:read` — default read
    * `:by_id` — single record by ID, preloads items, transactions, corrections, corrected_invoice
    * `:list_for_month` — by issue_date range, VAT only, correction merging
    * `:list_unmatched` — unmatched (no transactions, not skipped) in due_date range, VAT only
    * `:list_by_sale_date` — by sale_date range, preloads transactions
    * `:list_by_ids` — filter by ID list with optional date range, VAT only, correction merging
    * `:list_invoices_in_date_range` — invoices with issue_date OR sale_date in range
    * `:list_recent` — confirmed invoices from previous 2 months, correction merging
    * `:search` — ILIKE search with items having count > 0
    * `:by_share_token` — find by share token (cross-tenant)

  ## Public functions

    * `buyer_display_name/1` — display name for invoice buyer
    * `populate_logo_url/1` — loads organization avatar URL into `logo_url` field
    * `populate_reference_invoices/1` — builds correction chain with reference invoices
    * `get_latest_invoice_snapshot/1` — returns latest state of invoice (original or latest correction)
    * `get_currency_rate/1` — NBP exchange rate for non-PLN invoices
    * `get_net_value/1`, `get_vat_value/1`, `get_gross_value/1` — totals from items
    * `draft?/1`, `confirmed?/1`, `deletable?/1`, `ksef_submitted?/1`, `editable?/1`
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Accounts
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem, as: AshSalesInvoiceItem
  alias Firmowid.Ash.Resource
  alias Firmowid.Nbp
  alias Firmowid.SalesInvoices.CountryCodes
  alias Firmowid.SalesInvoices.SalesInvoice, as: EctoSalesInvoice

  require Ash.Query
  require Ecto.Query
  require Resource

  @snapshot_fields [
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

  postgres do
    table "sales_invoices"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :by_id, args: [:id], action: :by_id
    define :get, args: [:id], action: :by_id
    define :list_for_month, args: [:date_from, :date_to]
    define :list_unmatched, args: [{:optional, :date_from}, {:optional, :date_to}]
    define :list_by_sale_date, args: [:date_from, :date_to]
    define :list_by_ids, args: [:ids, {:optional, :date_from}, {:optional, :date_to}]
    define :list_invoices_in_date_range, args: [:date_from, :date_to]
    define :list_recent, args: []
    define :search, args: [:search_term]
    define :by_share_token, args: [:token]
  end

  actions do
    defaults [:read]

    read :by_id do
      get_by [:id]

      prepare build(
                load: [
                  :sales_invoice_items,
                  :transactions,
                  corrections: :sales_invoice_items,
                  corrected_invoice: :corrections
                ]
              )
    end

    read :list_for_month do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(
               ksef_invoice_kind == :vat and
                 issue_date >= ^arg(:date_from) and issue_date <= ^arg(:date_to)
             )

      prepare build(
                sort: [issue_date: :desc],
                load: [:sales_invoice_items, :transactions, corrections: :sales_invoice_items]
              )

      prepare after_action(&merge_corrections_after_read/3)
    end

    read :list_unmatched do
      argument :date_from, :date
      argument :date_to, :date

      prepare fn query, _context ->
        date_from = query.arguments[:date_from] || ~D[1970-01-01]
        date_to = query.arguments[:date_to] || ~D[2999-12-31]

        query
        |> Ash.Query.filter_input(%{
          ksef_invoice_kind: %{eq: :vat},
          due_date: %{greater_than_or_equal: date_from, less_than_or_equal: date_to},
          skip_invoicing: %{eq: false}
        })
        |> Ash.Query.sort(issue_date: :desc)
        |> Ash.Query.load([
          :sales_invoice_items,
          :transactions,
          corrections: :sales_invoice_items
        ])
      end

      prepare before_action(&filter_unmatched/2)
      prepare after_action(&merge_corrections_after_read/3)
    end

    read :list_by_sale_date do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(sale_date >= ^arg(:date_from) and sale_date <= ^arg(:date_to))
      prepare build(sort: [sale_date: :desc], load: [:transactions])
    end

    read :list_by_ids do
      argument :ids, {:array, :uuid_v7}, allow_nil?: false
      argument :date_from, :date
      argument :date_to, :date

      prepare fn query, _context ->
        ids = query.arguments.ids
        date_from = query.arguments[:date_from]
        date_to = query.arguments[:date_to]

        query = Ash.Query.filter_input(query, %{id: %{in: ids}, ksef_invoice_kind: %{eq: :vat}})

        query =
          if date_from do
            Ash.Query.filter_input(query, %{issue_date: %{greater_than_or_equal: date_from}})
          else
            query
          end

        query =
          if date_to do
            Ash.Query.filter_input(query, %{issue_date: %{less_than_or_equal: date_to}})
          else
            query
          end

        query
        |> Ash.Query.sort(issue_date: :desc)
        |> Ash.Query.load([
          :sales_invoice_items,
          :transactions,
          corrections: :sales_invoice_items
        ])
      end

      prepare after_action(&merge_corrections_after_read/3)
    end

    read :list_invoices_in_date_range do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(
               (issue_date >= ^arg(:date_from) and issue_date <= ^arg(:date_to)) or
                 (sale_date >= ^arg(:date_from) and sale_date <= ^arg(:date_to))
             )

      prepare build(sort: [issue_date: :desc])
    end

    read :list_recent do
      prepare fn query, _context ->
        today = Date.utc_today()
        range_end = %{today | day: 1}
        range_start = Date.shift(range_end, month: -2)

        query
        |> Ash.Query.filter_input(%{
          ksef_invoice_kind: %{eq: :vat},
          invoice_number: %{is_nil: false},
          issue_date: %{
            greater_than_or_equal: range_start,
            less_than: range_end
          }
        })
        |> Ash.Query.sort(issue_date: :desc, invoice_number: :desc)
        |> Ash.Query.load([
          :sales_invoice_items,
          :transactions,
          corrections: :sales_invoice_items
        ])
      end

      prepare after_action(&merge_corrections_after_read/3)
    end

    action :search, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]
      argument :search_term, :string, allow_nil?: false

      run fn input, context ->
        import Ecto.Query

        search_term = "%#{input.arguments.search_term}%"
        opts = Ash.Context.to_opts(context)
        tenant = opts[:tenant]

        results =
          EctoSalesInvoice
          |> where([i], i.organization_id == ^tenant)
          |> where(
            [i],
            ilike(i.invoice_number, ^search_term) or
              ilike(i.buyer_full_name, ^search_term) or
              ilike(i.buyer_given_name, ^search_term) or
              ilike(i.buyer_display_name, ^search_term) or
              ilike(i.buyer_surname, ^search_term) or
              ilike(i.buyer_address, ^search_term) or
              ilike(i.buyer_id, ^search_term) or
              ilike(i.buyer_pesel, ^search_term)
          )
          |> join(:left, [i], items in assoc(i, :sales_invoice_items))
          |> group_by([i], i.id)
          |> having([i, items], count(items.id) > 0)
          |> limit(15)
          |> order_by(desc: :updated_at)
          |> select([i], i.id)
          |> Firmowid.Repo.all(skip_organization_id: true)

        if results == [] do
          {:ok, []}
        else
          __MODULE__
          |> Ash.Query.filter_input(%{id: %{in: results}})
          |> Ash.Query.load([:sales_invoice_items])
          |> Ash.Query.sort(updated_at: :desc)
          |> Ash.read!(opts)
          |> then(&{:ok, &1})
        end
      end
    end

    action :by_share_token, :struct do
      constraints instance_of: __MODULE__
      argument :token, :string, allow_nil?: false

      run fn input, context ->
        import Ecto.Query

        token = input.arguments.token
        opts = Ash.Context.to_opts(context)

        {share_token, correction_id} =
          case String.split(token, ".", parts: 2) do
            [share_token] -> {share_token, nil}
            [share_token, correction_id] -> {share_token, correction_id}
          end

        invoice_id =
          if correction_id do
            EctoSalesInvoice
            |> where([i], i.id == ^correction_id and i.ksef_invoice_kind == :kor)
            |> join(:inner, [i], o in EctoSalesInvoice, on: o.share_token == ^share_token)
            |> select([i], i.id)
            |> Firmowid.Repo.one(skip_organization_id: true)
          else
            EctoSalesInvoice
            |> where([i], i.share_token == ^share_token)
            |> select([i], i.id)
            |> Firmowid.Repo.one(skip_organization_id: true)
          end

        case invoice_id do
          nil ->
            {:ok, nil}

          id ->
            result =
              __MODULE__
              |> Ash.Query.filter_input(%{id: %{eq: id}})
              |> Ash.Query.load([
                :organization,
                :sales_invoice_items,
                :transactions,
                corrections: :sales_invoice_items,
                corrected_invoice: :corrections
              ])
              |> Ash.read_one!(Keyword.delete(opts, :tenant))

            {:ok, result}
        end
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:action) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :invoice_type, :atom,
      constraints: [one_of: [:poland, :foreign]],
      default: :poland,
      public?: true

    attribute :invoice_number, :string, public?: true
    attribute :sale_date, :date, public?: true
    attribute :issue_date, :date, public?: true
    attribute :due_date, :date, public?: true

    attribute :payment_method, :atom,
      constraints: [one_of: ~w[cash card voucher check credit transfer mobile]a],
      default: :transfer,
      public?: true

    attribute :currency, :string, public?: true

    attribute :seller_nip, :string, public?: true
    attribute :seller_display_name, :string, public?: true
    attribute :seller_address, :string, public?: true
    attribute :seller_name, :string, public?: true
    attribute :seller_surname, :string, public?: true
    attribute :seller_account_number, :string, public?: true

    attribute :buyer_type, :atom,
      constraints: [one_of: [:individual, :company]],
      default: :company,
      public?: true

    attribute :buyer_id, :string, public?: true
    attribute :buyer_full_name, :string, public?: true
    attribute :buyer_given_name, :string, public?: true
    attribute :buyer_surname, :string, public?: true
    attribute :buyer_pesel, :string, public?: true
    attribute :buyer_display_name, :string, public?: true

    attribute :buyer_address, :string, public?: true
    attribute :buyer_country, :string, public?: true

    attribute :buyer_is_different_mail_address, :boolean, default: false, public?: true
    attribute :buyer_mail_address, :string, public?: true
    attribute :buyer_mail_country, :string, public?: true

    attribute :buyer_email, :string, public?: true
    attribute :buyer_phone, :string, public?: true
    attribute :buyer_description, :string, public?: true

    attribute :is_cash_account, :boolean, default: false, public?: true
    attribute :is_reverse_charge, :boolean, default: false, public?: true

    attribute :skip_invoicing, :boolean, default: false, public?: true

    attribute :item_names, :string, public?: true

    attribute :share_token, :string, public?: true

    # KSeF submission tracking
    attribute :ksef_number, :string, public?: true
    attribute :ksef_session_reference_number, :string, public?: true
    attribute :ksef_invoice_checksum, :string, public?: true
    attribute :locked_at, :utc_datetime, public?: true

    # KSeF FA(3) fields
    attribute :ksef_invoice_kind, :atom,
      constraints: [one_of: [:vat, :kor]],
      default: :vat,
      public?: true

    attribute :correction_reason, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :counterparty, Firmowid.Ash.Invoicing.Counterparty do
      attribute_writable? true
    end

    belongs_to :corrected_invoice, __MODULE__ do
      attribute_writable? true
    end

    has_many :corrections, __MODULE__ do
      source_attribute :id
      destination_attribute :corrected_invoice_id
      sort locked_at: :asc_nils_last, inserted_at: :asc
    end

    has_many :sales_invoice_items, AshSalesInvoiceItem do
      sort index: :asc
    end

    many_to_many :transactions, Firmowid.Ash.Finances.Transaction do
      through Firmowid.Ash.Invoicing.SalesInvoiceTransaction
      source_attribute_on_join_resource :sales_invoice_id
      destination_attribute_on_join_resource :transaction_id
    end

    has_many :entity_tags, Firmowid.Ash.Analysis.EntityTag do
      source_attribute :id
      destination_attribute :resource_id
    end
  end

  # Public functions -----------------------------------------------------------

  @doc """
  Returns the display name for the buyer on a sales invoice.

  Priority:
  1. `buyer_display_name` (if set)
  2. For companies: `buyer_full_name`
  3. For individuals: "buyer_given_name buyer_surname"
  """
  @spec buyer_display_name(struct() | map()) :: String.t() | nil
  def buyer_display_name(%{buyer_display_name: name}) when is_binary(name) and name != "", do: name

  def buyer_display_name(%{buyer_type: :company, buyer_full_name: name}) when is_binary(name), do: name

  def buyer_display_name(%{buyer_type: :individual, buyer_given_name: given_name, buyer_surname: surname})
      when is_binary(given_name) and is_binary(surname) do
    "#{given_name} #{surname}"
  end

  def buyer_display_name(_), do: nil

  @doc """
  Populates the `logo_url` virtual field by loading the organization's avatar.

  Returns nil if the invoice is nil.
  """
  @spec populate_logo_url(struct() | nil) :: struct() | nil
  def populate_logo_url(nil), do: nil

  def populate_logo_url(%{__struct__: __MODULE__} = invoice) do
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    loaded = Ash.load!(invoice, [:organization], authorize?: false, actor: %{})
    organization = Accounts.get_organization_with_avatar(loaded.organization)
    Map.put(invoice, :logo_url, organization.avatar_url)
  end

  @doc """
  Returns the currency exchange rate for a sales invoice.

  For PLN invoices, returns nil (no conversion needed).
  For other currencies, fetches the NBP exchange rate for the currency conversion date.
  """
  @spec get_currency_rate(struct()) :: map() | nil
  def get_currency_rate(%{currency: "PLN"}), do: nil

  def get_currency_rate(%{currency: currency, issue_date: issue_date, sale_date: sale_date}) do
    conversion_date = get_currency_conversion_date(issue_date, sale_date)
    Nbp.ApiClient.get_exchange_rate(currency, conversion_date)
  end

  @doc """
  Returns the currency conversion date for a sales invoice.
  """
  @spec get_currency_conversion_date(Date.t(), Date.t()) :: Date.t()
  def get_currency_conversion_date(issue_date, sale_date) do
    if Date.before?(issue_date, sale_date), do: issue_date, else: sale_date
  end

  @doc """
  Builds the correction chain, populating `reference_invoice` and `corrected_invoice`
  virtual fields on each correction in the chain.

  For VAT invoices: populates corrections with their reference invoices.
  For KOR invoices: populates both the reference and corrected invoice chain.
  """
  @spec populate_reference_invoices(struct()) :: struct()
  def populate_reference_invoices(%{__struct__: __MODULE__, ksef_invoice_kind: :vat} = invoice) do
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

  def populate_reference_invoices(%{__struct__: __MODULE__, ksef_invoice_kind: :kor} = invoice) do
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
      |> then(fn ref ->
        if is_list(ref.sales_invoice_items) and ref.sales_invoice_items != [] do
          ref
        else
          Ash.load!(ref, [:sales_invoice_items], authorize?: false, actor: %{})
        end
      end)

    %{invoice | reference_invoice: reference_invoice, corrected_invoice: original_invoice}
  end

  @doc """
  Returns the latest state (snapshot) of an invoice — either the latest correction
  or the original if no corrections exist.
  """
  @spec get_latest_invoice_snapshot(struct()) :: struct()
  def get_latest_invoice_snapshot(%{__struct__: __MODULE__, ksef_invoice_kind: :vat} = invoice) do
    invoice.corrections
    |> Enum.max_by(
      fn correction -> correction.locked_at || correction.inserted_at end,
      DateTime,
      fn -> invoice end
    )
    |> then(fn snapshot ->
      if is_list(snapshot.sales_invoice_items) and snapshot.sales_invoice_items != [] do
        snapshot
      else
        Ash.load!(snapshot, [:sales_invoice_items], authorize?: false, actor: %{})
      end
    end)
  end

  @doc "Returns the net value total across all items."
  @spec get_net_value(struct()) :: Decimal.t()
  def get_net_value(%{sales_invoice_items: items, currency: currency}) do
    currency
    |> Money.new(
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, AshSalesInvoiceItem.get_net_value(item))
      end)
    )
    |> Money.round()
    |> Money.to_decimal()
  end

  @doc "Returns the total VAT across all items."
  @spec get_vat_value(struct()) :: Decimal.t()
  def get_vat_value(%{sales_invoice_items: items, currency: currency}) do
    currency
    |> Money.new(
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, AshSalesInvoiceItem.get_vat_value(item))
      end)
    )
    |> Money.round()
    |> Money.to_decimal()
  end

  @doc "Returns the gross value (net + VAT) total."
  @spec get_gross_value(struct()) :: Decimal.t()
  def get_gross_value(%{currency: currency} = invoice) do
    currency
    |> Money.new(Decimal.add(get_net_value(invoice), get_vat_value(invoice)))
    |> Money.round()
    |> Money.to_decimal()
  end

  @doc "Returns true if the invoice is a draft (no invoice number)."
  @spec draft?(struct()) :: boolean()
  def draft?(%{invoice_number: nil}), do: true
  def draft?(%{invoice_number: _}), do: false

  @doc "Returns true if the invoice is confirmed (has an invoice number)."
  @spec confirmed?(struct()) :: boolean()
  def confirmed?(%{invoice_number: nil}), do: false
  def confirmed?(%{invoice_number: _}), do: true

  @doc "Returns true if the invoice can be deleted."
  @spec deletable?(struct()) :: boolean()
  def deletable?(%{ksef_number: nil, locked_at: nil}), do: true
  def deletable?(%{}), do: false

  @doc "Returns true if the invoice has been submitted to KSeF."
  @spec ksef_submitted?(struct()) :: boolean()
  def ksef_submitted?(%{ksef_number: nil}), do: false
  def ksef_submitted?(%{}), do: true

  @doc """
  Returns true if the invoice can be edited.

  Requires corrections preloaded for VAT invoices,
  and corrected_invoice with corrections for KOR invoices.
  """
  @spec editable?(struct()) :: boolean()
  def editable?(%{ksef_invoice_kind: :kor, corrected_invoice: %{corrections: corrections}} = invoice) do
    latest_correction = List.last(corrections)
    latest_correction != nil and latest_correction.id == invoice.id
  end

  def editable?(%{ksef_invoice_kind: :vat, corrections: corrections}) when is_list(corrections) do
    Enum.empty?(corrections)
  end

  def editable?(%{invoice_number: nil}), do: true
  def editable?(%{locked_at: nil}), do: true
  def editable?(%{}), do: false

  @doc "Returns true if the buyer is from an EU country."
  @spec buyer_from_eu?(struct()) :: boolean()
  def buyer_from_eu?(%{buyer_country: country}) when is_binary(country) do
    CountryCodes.eu_country?(country)
  end

  def buyer_from_eu?(_), do: false

  @doc "Returns the buyer's region (:eu, :non_eu, or :invalid)."
  @spec buyer_region(struct()) :: :eu | :non_eu | :invalid
  def buyer_region(%{buyer_country: country}) when is_binary(country) do
    CountryCodes.region(country)
  end

  def buyer_region(_), do: :invalid

  @doc "Returns the buyer ID type based on country, PESEL, and buyer type."
  @spec buyer_id_type(struct()) :: :nip | :eu_vat | :other_id | :optional_id | :no_id
  def buyer_id_type(%{buyer_type: buyer_type, buyer_pesel: buyer_pesel, buyer_country: buyer_country}) do
    CountryCodes.tax_id_type(buyer_country, buyer_pesel, buyer_type)
  end

  # Private helpers -----------------------------------------------------------

  defp filter_unmatched(query, _context) do
    Ash.Query.filter(query, count(transactions) == 0)
  end

  defp merge_corrections_after_read(_query, results, _context) do
    {:ok, Enum.map(results, &merge_latest_correction/1)}
  end

  defp merge_latest_correction(%{corrections: []} = invoice), do: invoice

  defp merge_latest_correction(%{corrections: corrections} = invoice) when is_list(corrections) do
    latest =
      Enum.max_by(corrections, fn c -> c.locked_at || c.inserted_at end, DateTime, fn -> nil end)

    if latest, do: Map.merge(invoice, Map.take(latest, @snapshot_fields)), else: invoice
  end

  defp merge_latest_correction(invoice), do: invoice
end
