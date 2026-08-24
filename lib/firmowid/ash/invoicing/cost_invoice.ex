# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
defmodule Firmowid.Ash.Invoicing.CostInvoice do
  @moduledoc """
  Ash resource for cost (purchase) invoices.

  ## Read Actions

    * `:read` — primary, with optional filters: `date_from`, `date_to`, `date_field`,
      `reconciliation` (`:pending`/`:matched`/`:skipped`), `ids`, `corrections`
      (`:include` corrections only, `:exclude` corrections, `nil` for both).
    * `:by_id` — single record by ID, preloads all relationships including blob URLs
    * `:by_checksum` — find by blob checksum (join on blobs)

  ## Write Actions

    * `:create` — create from AI-extracted or KSeF-parsed metadata
    * `:create_dedup` — create with KSeF-number deduplication via upsert
    * `:toggle_skip` — toggle the skip_invoicing flag
    * `:update_blob_id` — attach a blob to an existing invoice

  ## Calculations

    * `:is_ksef_imported` — whether the invoice was imported from KSeF
    * `:is_deletable` — whether the invoice can be deleted (not KSeF-imported)
    * `:effective_amount` — Money total including correction deltas
    * `:effective_seller_display_name`, etc. — latest correction snapshot fields

  ## Aggregates

    * `:corrections_amount` — Money sum of correction invoice deltas
    * `:latest_correction_*` — latest correction's snapshot fields (seller, dates, etc.)

  Orchestration functions (delete, upload, create, hydrate) live on the
  domain module `Firmowid.Ash.Invoicing`.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban, AshEvents.Events, AshJido],
    notifiers: [Ash.Notifier.PubSub],
    primary_read_warning?: false

  alias AshMoney.Types.Money, as: MoneyType
  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.IsSystemActor
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Invoicing.Changes.ComputeCostInvoiceDescription
  alias Firmowid.Ash.Invoicing.Changes.ComputeCostInvoiceSellerDisplayName
  alias Firmowid.Ash.Invoicing.Changes.EnqueueMissingCostInvoiceDescriptionRefresh
  alias Firmowid.Ash.Invoicing.Changes.RequireTransactionIds
  alias Firmowid.Ash.Invoicing.Changes.ValidateCostInvoiceCorrectionCurrency
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Resource

  require Resource

  @correction_invoice_types [:kor, :kor_zal, :kor_roz]

  postgres do
    table "cost_invoices"
    repo Firmowid.Repo

    references do
      reference :original_invoice, ignore?: true
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :refresh_missing_description do
        action :refresh_description
        read_action :read_global
        where expr(description == "")
        scheduler_cron "0 * * * *"
        max_attempts 2
        queue :cost_invoices

        worker_module_name Firmowid.Ash.Invoicing.CostInvoice.Worker.RefreshMissingDescription

        scheduler_module_name Firmowid.Ash.Invoicing.CostInvoice.Scheduler.RefreshMissingDescription
      end
    end
  end

  events do
    event_log Firmowid.Ash.Events.Event
    only_actions [:connect_transactions, :disconnect_transactions, :disconnect_all_transactions]
  end

  jido do
    action :read,
      name: "list_cost_invoices",
      description: "Listuje faktury kosztowe z bezpiecznymi filtrami Ash.",
      category: "ash.invoicing.read",
      tags: ["assistant", "cost_invoice"]

    action :by_id,
      name: "get_cost_invoice_by_id",
      description: "Pobiera fakturę kosztową po identyfikatorze.",
      category: "ash.invoicing.read",
      tags: ["assistant", "cost_invoice"]

    action :connect_transactions,
      name: "connect_cost_invoice_transactions",
      description: "Łączy fakturę kosztową z podanymi transakcjami.",
      category: "ash.invoicing.write",
      tags: ["assistant", "cost_invoice", "matching"]
  end

  code_interface do
    define :by_id, args: [:id], action: :by_id
    define :get, args: [:id], action: :by_id
    define :read, action: :read
    define :read_global, action: :read_global
    define :read_missing_description, action: :read_missing_description
    define :by_checksum, args: [:blob_checksum]
    define :create, action: :create
    define :toggle_skip, action: :toggle_skip
    define :update_internal_note, args: [:internal_note], action: :update_internal_note
    define :update_blob_id, args: [:blob_id], action: :update_blob_id
    define :refresh_seller_display_name, action: :refresh_seller_display_name
    define :refresh_description, action: :refresh_description
  end

  actions do
    # No `defaults [:read]` — the explicit `:read` below serves as primary
    read :read do
      description "List cost invoices with search and reconciliation filters."
      primary? true

      pagination do
        required? false
        keyset? true
      end

      argument :date_from, :date
      argument :date_to, :date
      argument :query, :string
      argument :currency, :string
      argument :amount_gt, :decimal
      argument :amount_lt, :decimal

      argument :date_field, :atom do
        constraints one_of: [:issue_date, :sale_date, :due_date, :any]
        default :issue_date
      end

      argument :reconciliation, :atom do
        constraints one_of: [:pending, :matched, :skipped]
      end

      argument :ids, {:array, :uuid_v7}
      argument :inserted_from, :utc_datetime
      argument :inserted_to, :utc_datetime

      argument :limit, :integer do
        constraints min: 1
      end

      argument :source, :atom do
        constraints one_of: [:manual_import, :ksef]
      end

      argument :in_digest, :atom do
        constraints one_of: [:yes, :no]
      end

      # Date filtering — conditional on date_field
      prepare {Firmowid.Ash.Invoicing.Preparations.FilterByDateField, []}
      prepare {Firmowid.Ash.Invoicing.Preparations.FilterBySourceAndDigestState, []}

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
               columns: ~w(seller seller_display_name description invoice_identifier)}

      prepare build(filter: expr(amount[:currency_code] == ^arg(:currency))) do
        where present(:currency)
      end

      prepare build(filter: expr(amount[:amount] >= ^arg(:amount_gt))) do
        where present(:amount_gt)
      end

      prepare build(filter: expr(amount[:amount] <= ^arg(:amount_lt))) do
        where present(:amount_lt)
      end

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

      prepare build(filter: expr(inserted_at >= ^arg(:inserted_from))) do
        where present(:inserted_from)
      end

      prepare build(filter: expr(inserted_at < ^arg(:inserted_to))) do
        where present(:inserted_to)
      end

      prepare build(sort: [issue_date: :desc]) do
        where absent(:query)
      end

      prepare build(limit: arg(:limit)) do
        where present(:limit)
      end

      argument :corrections, :atom do
        constraints one_of: [:include, :exclude]
      end

      # :exclude — hide corrections that are linked to an existing original invoice
      prepare build(filter: expr(is_nil(original_invoice_ksef_number) or is_nil(original_invoice.id))) do
        where argument_equals(:corrections, :exclude)
      end

      # :include — show only corrections linked to an existing original invoice
      prepare build(
                filter:
                  expr(
                    not is_nil(original_invoice_ksef_number) and
                      not is_nil(original_invoice.id)
                  )
              ) do
        where argument_equals(:corrections, :include)
      end
    end

    read :by_id do
      description "Fetch a cost invoice by ID."
      get_by [:id]
    end

    read :by_checksum do
      description "Find a cost invoice by its blob's SHA-256 checksum."
      get? true

      argument :blob_checksum, :string, allow_nil?: false

      filter expr(exists(blob, blob_checksum == ^arg(:blob_checksum)))
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :read_missing_description do
      description "Scoped scheduler read for cost invoices missing generated descriptions."

      pagination do
        required? false
        keyset? true
      end
    end

    # -- Write actions --------------------------------------------------------

    create :create do
      description "Create a cost invoice from imported or extracted metadata."
      primary? true

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
        :items_list,
        :amount,
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
        :payment_method,
        :internal_note
      ]

      validate present([
                 :seller,
                 :sale_date,
                 :issue_date,
                 :items_list,
                 :amount,
                 :invoice_identifier
               ])

      change ComputeCostInvoiceSellerDisplayName

      change ComputeCostInvoiceDescription

      change ValidateCostInvoiceCorrectionCurrency

      change EnqueueMissingCostInvoiceDescriptionRefresh

      change fn changeset, _context ->
        validate_non_correction_amount_sign(changeset)
      end

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    create :create_dedup do
      description "Create a cost invoice, detecting KSeF number duplicates via upsert."

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
        :items_list,
        :amount,
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
        :payment_method,
        :internal_note
      ]

      upsert? true
      upsert_identity :ksef_number
      upsert_fields []

      validate present([
                 :seller,
                 :sale_date,
                 :issue_date,
                 :items_list,
                 :amount,
                 :invoice_identifier
               ])

      change ComputeCostInvoiceSellerDisplayName

      change ComputeCostInvoiceDescription

      change ValidateCostInvoiceCorrectionCurrency

      change fn changeset, _context ->
        validate_non_correction_amount_sign(changeset)
      end

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    update :toggle_skip do
      description "Toggle whether this cost invoice is skipped during invoicing workflows."
      require_atomic? false

      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :skip_invoicing)
        Ash.Changeset.force_change_attribute(changeset, :skip_invoicing, !current)
      end
    end

    update :update_blob_id do
      description "Attach or replace the source blob for this cost invoice."
      accept [:blob_id]
      require_atomic? false
    end

    update :update_internal_note do
      description "Update the internal note stored on this cost invoice."
      primary? true
      accept [:internal_note]
      require_atomic? false

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    update :refresh_description do
      description "Recompute the generated description for this cost invoice."
      require_atomic? false

      change ComputeCostInvoiceDescription
    end

    update :refresh_seller_display_name do
      description "Recompute the seller display name for this cost invoice."
      require_atomic? false

      change ComputeCostInvoiceSellerDisplayName
    end

    update :connect_transactions do
      description "Connect transactions to this cost invoice via the join table."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      change RequireTransactionIds
      change manage_relationship(:transaction_ids, :transactions, type: :append)
    end

    update :disconnect_transactions do
      description "Disconnect the provided transactions from this cost invoice."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      change RequireTransactionIds
      change manage_relationship(:transaction_ids, :transactions, type: :remove)
    end

    update :disconnect_all_transactions do
      description "Disconnect all transactions from this cost invoice."
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.manage_relationship(changeset, :transactions, [], on_missing: :unrelate)
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass AshObanInteraction do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor]} do
      authorize_if always()
    end

    bypass {SystemActorRole,
            roles: [
              :ksef_session,
              :invoice_matcher,
              :analysis_reader,
              :ksef_digest,
              :billing_snapshotter
            ]} do
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:ksef_session]} do
      authorize_if action(:create)
    end

    bypass {SystemActorRole, roles: [:invoice_matcher]} do
      authorize_if action([
                     :connect_transactions,
                     :disconnect_transactions,
                     :disconnect_all_transactions
                   ])
    end

    policy [
      action([:connect_transactions, :disconnect_transactions, :disconnect_all_transactions]),
      {AtLeastRole, role: :invoicing}
    ] do
      authorize_if always()
    end

    # Other system actors: no access
    policy IsSystemActor do
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

    publish :create, ["created", :_tenant]
    publish :toggle_skip, ["updated", :_tenant]
    publish :update_blob_id, ["updated", :_tenant]
    publish :update_internal_note, ["updated", :_tenant]
    publish :refresh_seller_display_name, ["updated", :_tenant]
    publish :refresh_description, ["updated", :_tenant]
    publish :connect_transactions, ["updated", :_tenant]
    publish :disconnect_transactions, ["updated", :_tenant]
    publish :disconnect_all_transactions, ["updated", :_tenant]
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

    attribute :amount, MoneyType, public?: true, allow_nil?: false

    attribute :description, :string, public?: true, allow_nil?: false, default: ""
    attribute :invoice_identifier, :string, public?: true
    attribute :internal_note, :string, public?: true

    attribute :items_list, {:array, :map}, public?: true, allow_nil?: false, default: []

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
      allow_nil? true
      attribute_writable? true
      define_attribute? false
      source_attribute :blob_id
    end

    belongs_to :inbound_email, Firmowid.Ash.Invoicing.InboundEmail do
      allow_nil? true
      attribute_writable? true
      define_attribute? false
      source_attribute :inbound_email_id
    end

    many_to_many :transactions, Firmowid.Ash.Finances.Transaction do
      through CostInvoiceTransaction
      source_attribute_on_join_resource :cost_invoice_id
      destination_attribute_on_join_resource :transaction_id
    end

    # Named :correction_invoices (not :corrections as in SalesInvoice) because
    # cost invoice corrections link via ksef_number, not a direct FK.
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
      allow_nil? true
      attribute_writable? true
      define_attribute? false
      source_attribute :original_invoice_ksef_number
      destination_attribute :ksef_number
    end

    has_many :entity_tags, Firmowid.Ash.Analysis.EntityTag do
      source_attribute :id
      destination_attribute :resource_id
    end

    has_one :ksef_invoice_digest_item, Firmowid.Ash.Invoicing.KsefInvoiceDigestItem do
      source_attribute :id
      destination_attribute :cost_invoice_id
    end
  end

  calculations do
    calculate :is_ksef_imported,
              :boolean,
              expr(
                not (is_nil(ksef_downloaded_at) and is_nil(ksef_permanent_storage_date) and
                       is_nil(ksef_number))
              )

    calculate :invoice_source,
              :string,
              expr(
                if is_ksef_imported do
                  "ksef"
                else
                  "document"
                end
              )

    calculate :is_in_ksef_digest,
              :boolean,
              expr(exists(ksef_invoice_digest_item, true))

    calculate :is_deletable,
              :boolean,
              expr(not is_ksef_imported)

    # Effective fields — coalesce latest correction snapshot with original.
    # DB-pushable, filterable, sortable.
    calculate :has_corrections, :boolean, expr(not is_nil(corrections_amount))

    calculate :effective_amount,
              MoneyType,
              expr(
                if is_nil(corrections_amount) do
                  amount
                else
                  amount + corrections_amount
                end
              )

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
    sum :corrections_amount, :correction_invoices, :amount

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

  # Cost invoices represent money going out, so amount is stored as negative
  # (convention matching bank transaction sign). A positive amount on a
  # non-correction invoice is invalid — only corrections may flip the sign.
  defp validate_non_correction_amount_sign(changeset) do
    invoice_type = Ash.Changeset.get_attribute(changeset, :invoice_type)
    amount = Ash.Changeset.get_attribute(changeset, :amount)

    cond do
      invoice_type in @correction_invoice_types ->
        changeset

      is_nil(amount) or Money.positive?(amount) ->
        Ash.Changeset.add_error(changeset,
          field: :amount,
          message: "must be <= 0 for non-correction invoices"
        )

      true ->
        changeset
    end
  end
end
