defmodule Firmowid.Ash.Invoicing.CostInvoice do
  @moduledoc """
  Ash resource for cost (purchase) invoices.

  Read-only in this slice — mutations remain in the legacy `CostInvoices` Ecto
  context until Slice 6.

  ## Actions

    * `:read` — default read
    * `:by_id` — single record by ID, preloads transactions
    * `:list_for_month` — by issue_date range, excludes linked corrections,
      merges corrections into originals, preloads transactions + corrections
    * `:list_unmatched` — unmatched (no transactions, not skipped) in due_date range,
      excludes linked corrections, merges corrections
    * `:list_by_sale_date` — by sale_date range, preloads transactions
    * `:list_by_ids` — filter by ID list with optional date range
    * `:list_invoices_in_date_range` — invoices with blobs in issue/sale date range,
      returns with blob_url loaded
    * `:by_checksum` — find by blob checksum (join on blobs)
    * `:get_with_blob_url` — single record with blob_url, transactions, corrections, original_invoice

  ## Calculations

    * `:blob_url` — presigned S3 URL for the attached blob
    * `:ksef_imported` — whether the invoice was imported from KSeF
    * `:deletable` — whether the invoice can be deleted (not KSeF-imported)

  ## Public functions

    * `merge_corrections_into_original_invoice/1` — folds correction invoice
      data (amounts, dates, seller info) into the original invoice struct.
    * `ksef_imported?/1` — predicate check on struct fields.
    * `deletable?/1` — inverse of `ksef_imported?/1`.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Blobs.Blob, as: AshBlob
  alias Firmowid.Ash.Resource
  alias Firmowid.CostInvoices.CostInvoice, as: EctoCostInvoice

  require Ash.Query
  require Ecto.Query
  require Resource

  @correction_invoice_types [:kor, :kor_zal, :kor_roz]

  postgres do
    table "cost_invoices"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :by_id, args: [:id], action: :by_id
    define :get, args: [:id], action: :by_id
    define :list_for_month, args: [:date_from, :date_to]
    define :list_unmatched, args: [:date_from, :date_to]
    define :list_by_sale_date, args: [:date_from, :date_to]
    define :list_by_ids, args: [:ids, {:optional, :date_from}, {:optional, :date_to}]
    define :list_invoices_in_date_range, args: [:date_from, :date_to]
    define :by_checksum, args: [:blob_checksum]
    define :get_with_blob_url, args: [:id], action: :get_with_blob_url
  end

  actions do
    defaults [:read]

    read :by_id do
      get_by [:id]
    end

    read :list_for_month do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(issue_date >= ^arg(:date_from) and issue_date <= ^arg(:date_to))
      prepare build(sort: [issue_date: :desc], load: [:transactions, :correction_invoices])
      prepare before_action(&exclude_linked_corrections/2)
      prepare after_action(&merge_corrections_after_read/3)
    end

    read :list_unmatched do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(
               due_date >= ^arg(:date_from) and due_date <= ^arg(:date_to) and
                 skip_invoicing == false
             )

      prepare build(sort: [issue_date: :desc], load: [:transactions, :correction_invoices])
      prepare before_action(&exclude_linked_corrections/2)
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

        query = Ash.Query.filter_input(query, %{id: %{in: ids}})

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
        |> Ash.Query.load(:transactions)
      end
    end

    read :list_invoices_in_date_range do
      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      filter expr(
               not is_nil(blob_id) and
                 ((issue_date >= ^arg(:date_from) and issue_date <= ^arg(:date_to)) or
                    (sale_date >= ^arg(:date_from) and sale_date <= ^arg(:date_to)))
             )

      prepare build(load: [blob: [:url]])
    end

    action :by_checksum, :struct do
      constraints instance_of: __MODULE__
      argument :blob_checksum, :string, allow_nil?: false

      run fn input, context ->
        import Ecto.Query

        result =
          Firmowid.Repo.one!(
            from(c in EctoCostInvoice,
              join: b in Firmowid.Blobs.Blob,
              on: b.id == c.blob_id,
              where: b.blob_checksum == ^input.arguments.blob_checksum
            )
          )

        # Convert to Ash struct
        __MODULE__
        |> Ash.Query.filter_input(%{id: %{eq: result.id}})
        |> Ash.Query.load([:blob])
        |> Ash.read_one!(Ash.Context.to_opts(context))
        |> then(&{:ok, &1})
      end
    end

    action :get_with_blob_url, :struct do
      constraints instance_of: __MODULE__
      argument :id, :uuid_v7, allow_nil?: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        invoice =
          __MODULE__
          |> Ash.Query.filter_input(%{id: %{eq: input.arguments.id}})
          |> Ash.Query.load([
            :transactions,
            :original_invoice,
            blob: [:url],
            correction_invoices: [blob: [:url]]
          ])
          |> Ash.read_one!(opts)

        {:ok, invoice}
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :seller, :string, public?: true
    attribute :seller_address, :string, public?: true
    attribute :seller_display_name, :string, public?: true
    attribute :account_number, :string, public?: true

    attribute :sale_date, :date, public?: true
    attribute :issue_date, :date, public?: true
    attribute :due_date, :date, public?: true

    attribute :total_amount, :decimal, public?: true
    attribute :currency, :string, public?: true

    attribute :description, :string, public?: true
    attribute :invoice_identifier, :string, public?: true

    attribute :skip_invoicing, :boolean, default: false, public?: true

    attribute :ksef_number, :string, public?: true
    attribute :ksef_permanent_storage_date, :naive_datetime, public?: true
    attribute :ksef_downloaded_at, :utc_datetime_usec, public?: true

    attribute :seller_nip, :string, public?: true
    attribute :seller_country_code, :string, public?: true
    attribute :seller_email, :string, public?: true
    attribute :seller_phone, :string, public?: true

    attribute :invoice_type, :atom,
      public?: true,
      constraints: [one_of: ~w(vat kor zal roz upr kor_zal kor_roz)a]

    attribute :original_invoice_ksef_number, :string, public?: true

    attribute :payment_method, :atom,
      public?: true,
      constraints: [one_of: ~w(cash card voucher check loan bank_transfer mobile)a]

    attribute :blob_id, :uuid, public?: true
    attribute :inbound_email_id, :uuid, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :blob, AshBlob do
      attribute_writable? true
      define_attribute? false
      source_attribute :blob_id
    end

    belongs_to :inbound_email, Firmowid.Ash.Invoicing.InboundEmail do
      attribute_writable? true
      define_attribute? false
      source_attribute :inbound_email_id
    end

    many_to_many :transactions, Firmowid.Ash.Finances.Transaction do
      through Firmowid.Ash.Invoicing.CostInvoiceTransaction
      source_attribute_on_join_resource :cost_invoice_id
      destination_attribute_on_join_resource :transaction_id
    end

    has_many :correction_invoices, __MODULE__ do
      source_attribute :ksef_number
      destination_attribute :original_invoice_ksef_number
      sort ksef_permanent_storage_date: :asc
    end

    belongs_to :original_invoice, __MODULE__ do
      attribute_writable? true
      define_attribute? false
      source_attribute :original_invoice_ksef_number
      destination_attribute :ksef_number
    end

    has_many :entity_tags, Firmowid.Ash.Analysis.EntityTag do
      source_attribute :id
      destination_attribute :resource_id
    end
  end

  calculations do
    calculate :ksef_imported,
              :boolean,
              expr(
                not (is_nil(ksef_downloaded_at) and is_nil(ksef_permanent_storage_date) and
                       is_nil(ksef_number))
              )

    calculate :deletable,
              :boolean,
              expr(not ksef_imported)
  end

  # Public functions -----------------------------------------------------------

  @doc """
  Returns true when invoice data was imported from KSeF FA(3) XML.
  """
  @spec ksef_imported?(struct()) :: boolean()
  def ksef_imported?(%{ksef_downloaded_at: nil, ksef_permanent_storage_date: nil, ksef_number: nil}), do: false

  def ksef_imported?(%{}), do: true

  @doc """
  Returns true if the invoice can be deleted (not KSeF-imported).
  """
  @spec deletable?(struct()) :: boolean()
  def deletable?(invoice), do: not ksef_imported?(invoice)

  @doc """
  Returns true if the invoice is a correction type.
  """
  @spec correction_invoice?(struct()) :: boolean()
  def correction_invoice?(%{invoice_type: invoice_type}), do: invoice_type in @correction_invoice_types

  @doc """
  Folds correction invoice data into the original invoice struct.

  When an original invoice has correction invoices, the total amount is summed
  (unless currencies differ), and seller/date fields are taken from the latest
  correction snapshot.
  """
  @spec merge_corrections_into_original_invoice(struct()) :: struct()
  def merge_corrections_into_original_invoice(%{correction_invoices: []} = invoice), do: invoice

  def merge_corrections_into_original_invoice(%{correction_invoices: corrections} = invoice) when is_list(corrections) do
    currency_changed? = Enum.any?(corrections, &(&1.currency != invoice.currency))

    total_amount =
      if currency_changed? do
        invoice.total_amount
      else
        Enum.reduce(corrections, invoice.total_amount, fn correction, acc ->
          Decimal.add(acc, correction.total_amount)
        end)
      end

    latest_snapshot =
      Enum.max_by(corrections, & &1.ksef_permanent_storage_date, NaiveDateTime, fn -> invoice end)

    %{
      invoice
      | total_amount: total_amount,
        currency: latest_snapshot.currency,
        sale_date: latest_snapshot.sale_date,
        due_date: latest_snapshot.due_date,
        seller: latest_snapshot.seller,
        seller_address: latest_snapshot.seller_address,
        seller_display_name: latest_snapshot.seller_display_name,
        seller_nip: latest_snapshot.seller_nip,
        seller_country_code: latest_snapshot.seller_country_code,
        seller_email: latest_snapshot.seller_email,
        seller_phone: latest_snapshot.seller_phone,
        payment_method: latest_snapshot.payment_method,
        account_number: latest_snapshot.account_number
    }
  end

  def merge_corrections_into_original_invoice(invoice), do: invoice

  # Private helpers -----------------------------------------------------------

  # Excludes corrections whose original invoice exists in the system.
  # Orphaned corrections (original deleted) and standalone corrections
  # (nil original_invoice_ksef_number) remain visible.
  defp exclude_linked_corrections(query, _context) do
    Ash.Query.filter(
      query,
      is_nil(original_invoice_ksef_number) or is_nil(original_invoice.id)
    )
  end

  # Filters to invoices that have no linked transactions.
  defp filter_unmatched(query, _context) do
    Ash.Query.filter(query, count(transactions) == 0)
  end

  defp merge_corrections_after_read(_query, results, _context) do
    {:ok, Enum.map(results, &merge_corrections_into_original_invoice/1)}
  end
end
