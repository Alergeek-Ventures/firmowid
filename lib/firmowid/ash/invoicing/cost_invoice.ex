defmodule Firmowid.Ash.Invoicing.CostInvoice do
  @moduledoc """
  Ash resource for cost (purchase) invoices.

  ## Read Actions

    * `:read` — primary, with optional filters: `date_from`, `date_to`, `date_field`,
      `reconciliation` (`:pending`/`:matched`/`:skipped`), `ids`. Excludes linked
      corrections automatically.
    * `:by_id` — single record by ID, preloads all relationships including blob URLs
    * `:by_checksum` — find by blob checksum (join on blobs)

  ## Write Actions

    * `:create_from_metadata` — create from AI-extracted or KSeF-parsed metadata
    * `:toggle_skip` — toggle the skip_invoicing flag
    * `:update_blob_id` — attach a blob to an existing invoice

  ## Calculations

    * `:is_ksef_imported` — whether the invoice was imported from KSeF
    * `:is_deletable` — whether the invoice can be deleted (not KSeF-imported)
    * `:effective_total_amount` — total including corrections (same-currency sum)
    * `:effective_currency`, `:effective_seller_display_name`, etc. — latest correction snapshot fields

  ## Aggregates

    * `:corrections_total_amount` — sum of correction invoice amounts
    * `:latest_correction_*` — latest correction's snapshot fields (seller, dates, etc.)

  Orchestration functions (delete, upload, create, hydrate) live on the
  domain module `Firmowid.Ash.Invoicing`.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    primary_read_warning?: false

  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Resource

  require Ash.Query
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
    define :read, action: :read
    define :by_checksum, args: [:blob_checksum]
    define :create_from_metadata, args: [:metadata], action: :create_from_metadata
    define :toggle_skip, action: :toggle_skip
    define :update_blob_id, args: [:blob_id], action: :update_blob_id
  end

  actions do
    # No `defaults [:read]` — the explicit `:read` below serves as primary
    read :read do
      primary? true

      argument :date_from, :date
      argument :date_to, :date

      argument :date_field, :atom do
        constraints one_of: [:issue_date, :sale_date, :due_date, :any]
        default :issue_date
      end

      argument :reconciliation, :atom do
        constraints one_of: [:pending, :matched, :skipped]
      end

      argument :ids, {:array, :uuid_v7}

      # Date filtering — conditional on date_field
      prepare {Firmowid.Ash.Invoicing.Preparations.FilterByDateField, []}

      # :pending — no linked transactions, not skipped
      prepare build(
                filter:
                  expr(
                    not exists(transactions, true) and
                      skip_invoicing == false
                  )
              ) do
        where argument_equals(:reconciliation, :pending)
      end

      # :matched — linked to at least one transaction
      prepare build(filter: expr(exists(transactions, true))) do
        where argument_equals(:reconciliation, :matched)
      end

      # :skipped — no linked transactions, skipped
      prepare build(
                filter:
                  expr(
                    not exists(transactions, true) and
                      skip_invoicing == true
                  )
              ) do
        where argument_equals(:reconciliation, :skipped)
      end

      # Filter by IDs
      prepare build(filter: expr(id in ^arg(:ids))) do
        where present(:ids)
      end

      prepare build(sort: [issue_date: :desc])

      # Exclude corrections linked to an original invoice — they are merged
      # into the original for display. Uses before_action (not static filter)
      # because `original_invoice.id` would recurse through the primary :read.
      prepare before_action(fn query, _context ->
                Ash.Query.filter(
                  query,
                  is_nil(original_invoice_ksef_number) or is_nil(original_invoice.id)
                )
              end)
    end

    read :by_id do
      get_by [:id]
    end

    read :by_checksum do
      description "Find a cost invoice by its blob's SHA-256 checksum."
      get? true

      argument :blob_checksum, :string, allow_nil?: false

      filter expr(exists(blob, blob_checksum == ^arg(:blob_checksum)))
    end

    read :search do
      description "Full-text BM25 search for cost invoices with optional filters."

      argument :query, :string
      argument :currency, :string
      argument :amount_gt, :decimal
      argument :amount_lt, :decimal
      argument :date_from, :date
      argument :date_to, :date
      argument :only_unmatched, :boolean

      # ParadeDB BM25 search
      prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
               columns: ~w(seller seller_display_name description invoice_identifier)}

      # Conditional filters
      prepare build(filter: expr(currency == ^arg(:currency))) do
        where present(:currency)
      end

      prepare build(filter: expr(total_amount >= ^arg(:amount_gt))) do
        where present(:amount_gt)
      end

      prepare build(filter: expr(total_amount <= ^arg(:amount_lt))) do
        where present(:amount_lt)
      end

      prepare build(filter: expr(issue_date >= ^arg(:date_from))) do
        where present(:date_from)
      end

      prepare build(filter: expr(issue_date <= ^arg(:date_to))) do
        where present(:date_to)
      end

      # Unmatched: no linked transactions and not skipped
      prepare build(
                filter:
                  expr(
                    not exists(transactions, true) and
                      skip_invoicing == false
                  )
              ) do
        where argument_equals(:only_unmatched, true)
      end

      prepare build(sort: [issue_date: :desc])
      prepare build(limit: 50)
    end

    # -- Write actions --------------------------------------------------------

    action :create_from_metadata, :struct do
      constraints instance_of: __MODULE__
      argument :metadata, :map, allow_nil?: false

      run fn input, context ->
        metadata = input.arguments.metadata
        opts = Ash.Context.to_opts(context)

        cost_invoice =
          __MODULE__
          |> Ash.Changeset.for_create(:create_internal, metadata, opts)
          |> Ash.create!()

        {:ok, cost_invoice}
      end
    end

    create :create_internal do
      accept [
        :blob_id,
        :inbound_email_id,
        :seller,
        :seller_address,
        :seller_display_name,
        :account_number,
        :sale_date,
        :issue_date,
        :due_date,
        :total_amount,
        :currency,
        :description,
        :invoice_identifier,
        :skip_invoicing,
        :ksef_number,
        :ksef_permanent_storage_date,
        :ksef_downloaded_at,
        :seller_nip,
        :seller_country_code,
        :seller_email,
        :seller_phone,
        :invoice_type,
        :original_invoice_ksef_number,
        :payment_method
      ]

      validate present([
                 :seller,
                 :seller_display_name,
                 :sale_date,
                 :issue_date,
                 :total_amount,
                 :currency,
                 :description,
                 :invoice_identifier
               ])

      change fn changeset, _context ->
        validate_non_correction_total_amount_sign(changeset)
      end
    end

    update :toggle_skip do
      require_atomic? false

      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :skip_invoicing)
        Ash.Changeset.force_change_attribute(changeset, :skip_invoicing, !current)
      end
    end

    update :update_blob_id do
      accept [:blob_id]
      require_atomic? false
    end

    update :connect_transactions do
      description "Connect transactions to this cost invoice via the join table."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      change manage_relationship(:transaction_ids, :transactions, type: :append)
    end

    update :disconnect_transactions do
      description "Disconnect all transactions from this cost invoice."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, default: []

      change manage_relationship(:transaction_ids, :transactions, type: :append_and_remove)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # cost_invoice_processor: full access
    bypass {SystemActorRole, roles: [:cost_invoice_processor]} do
      authorize_if always()
    end

    # ksef_session: read + create_internal
    bypass {SystemActorRole, roles: [:ksef_session]} do
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:ksef_session]} do
      authorize_if action(:create_internal)
    end

    # invoice_matcher: read + connect/disconnect transactions
    bypass {SystemActorRole, roles: [:invoice_matcher]} do
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:invoice_matcher]} do
      authorize_if action([:connect_transactions, :disconnect_transactions])
    end

    # Other system actors: no access
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # :invoicing and :accountant: read-only
    policy [action_type(:read), {AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # :accountant: write actions
    policy [
      action_type([:create, :update]),
      {AtLeastRole, role: :accountant}
    ] do
      authorize_if always()
    end

    policy [action_type(:action), {AtLeastRole, role: :accountant}] do
      authorize_if always()
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "cost_invoice"

    publish :create_internal, ["created", :_tenant]
    publish :toggle_skip, ["updated", :_tenant]
    publish :update_blob_id, ["updated", :_tenant]
    publish :connect_transactions, ["updated", :_tenant]
    publish :disconnect_transactions, ["updated", :_tenant]
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

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
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
      through CostInvoiceTransaction
      source_attribute_on_join_resource :cost_invoice_id
      destination_attribute_on_join_resource :transaction_id
    end

    has_many :correction_invoices, __MODULE__ do
      source_attribute :ksef_number
      destination_attribute :original_invoice_ksef_number
      sort ksef_permanent_storage_date: :asc
    end

    has_one :latest_correction_invoice, __MODULE__ do
      source_attribute :ksef_number
      destination_attribute :original_invoice_ksef_number
      sort ksef_permanent_storage_date: :desc
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
    calculate :is_ksef_imported,
              :boolean,
              expr(
                not (is_nil(ksef_downloaded_at) and is_nil(ksef_permanent_storage_date) and
                       is_nil(ksef_number))
              )

    calculate :is_deletable,
              :boolean,
              expr(not is_ksef_imported)

    # Effective fields — coalesce latest correction snapshot with original.
    # DB-pushable, filterable, sortable.
    calculate :has_corrections, :boolean, expr(not is_nil(corrections_total_amount))

    calculate :effective_total_amount,
              :decimal,
              expr(
                cond do
                  # No corrections
                  is_nil(corrections_total_amount) ->
                    total_amount

                  # Currency changed in correction — keep original amount
                  not is_nil(latest_correction_currency) and
                      latest_correction_currency != currency ->
                    total_amount

                  # Sum original + corrections
                  true ->
                    total_amount + corrections_total_amount
                end
              )

    calculate :effective_currency, :string, expr(latest_correction_currency || currency)

    calculate :effective_sale_date, :date, expr(latest_correction_sale_date || sale_date)

    calculate :effective_due_date, :date, expr(latest_correction_due_date || due_date)

    calculate :effective_seller, :string, expr(latest_correction_seller || seller)

    calculate :effective_seller_address,
              :string,
              expr(latest_correction_seller_address || seller_address)

    calculate :effective_seller_display_name,
              :string,
              expr(latest_correction_seller_display_name || seller_display_name)

    calculate :effective_seller_nip, :string, expr(latest_correction_seller_nip || seller_nip)

    calculate :effective_seller_country_code,
              :string,
              expr(latest_correction_seller_country_code || seller_country_code)

    calculate :effective_seller_email,
              :string,
              expr(latest_correction_seller_email || seller_email)

    calculate :effective_seller_phone,
              :string,
              expr(latest_correction_seller_phone || seller_phone)

    calculate :effective_payment_method,
              :atom,
              expr(latest_correction_payment_method || payment_method)

    calculate :effective_account_number,
              :string,
              expr(latest_correction_account_number || account_number)
  end

  aggregates do
    sum :corrections_total_amount, :correction_invoices, :total_amount

    first :latest_correction_currency, :correction_invoices, :currency do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_sale_date, :correction_invoices, :sale_date do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_due_date, :correction_invoices, :due_date do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_seller, :correction_invoices, :seller do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_seller_address, :correction_invoices, :seller_address do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_seller_display_name, :correction_invoices, :seller_display_name do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_seller_nip, :correction_invoices, :seller_nip do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_seller_country_code, :correction_invoices, :seller_country_code do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_seller_email, :correction_invoices, :seller_email do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_seller_phone, :correction_invoices, :seller_phone do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_payment_method, :correction_invoices, :payment_method do
      sort ksef_permanent_storage_date: :desc
    end

    first :latest_correction_account_number, :correction_invoices, :account_number do
      sort ksef_permanent_storage_date: :desc
    end
  end

  identities do
    identity :ksef_number, [:ksef_number], nils_distinct?: true
  end

  defp validate_non_correction_total_amount_sign(changeset) do
    invoice_type = Ash.Changeset.get_attribute(changeset, :invoice_type)
    total_amount = Ash.Changeset.get_attribute(changeset, :total_amount)

    cond do
      invoice_type in @correction_invoice_types ->
        changeset

      is_nil(total_amount) or Decimal.gt?(total_amount, 0) ->
        Ash.Changeset.add_error(changeset,
          field: :total_amount,
          message: "must be <= 0 for non-correction invoices"
        )

      true ->
        changeset
    end
  end
end
