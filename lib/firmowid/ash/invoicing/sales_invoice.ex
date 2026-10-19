# credo:disable-for-this-file ExDNA.Credo
# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
# This resource centralizes invoice lifecycle, numbering, and KSeF behaviors; reducing
# duplication requires extracting multiple actions/helpers into shared modules across boundaries.
defmodule Firmowid.Ash.Invoicing.SalesInvoice do
  @moduledoc """
  Ash resource for sales invoices.

  ## Read Actions

    * `:read` — basic primary read for framework and relationship reads
    * `:list` — application listing with optional filters: `date_from`, `date_to`,
      `date_field` (`:issue_date` | `:sale_date` | `:due_date` | `:any`),
      `kind` (`:vat` | `:kor`), `status` (`:unmatched` | `:confirmed`), `ids`,
      `inserted_from` (inclusive), `inserted_to` (exclusive)
    * `:by_id` — single record by ID, preloads items, transactions, corrections, corrected_invoice
    * `:by_share_token` — find by share token (cross-tenant)

  ## Write Actions

  Creates name where an invoice comes from, updates name a move between its states.

    * `:draft` — save a complete, unnumbered VAT invoice
    * `:issue` — issue a new invoice today and queue its KSeF submission atomically
    * `:correct` — issue a correction invoice (KOR) and queue its KSeF submission
    * `:import_from_ksef` — record an invoice issued outside Firmowid that KSeF already stores
    * `:revise` — revise a saved draft
    * `:finalize` — number a draft, issued today, and queue its KSeF submission atomically
    * `:return_to_draft` — withdraw an invoice KSeF did not accept back to a draft
    * `:destroy` — delete invoice (only if not KSeF-submitted)
    * `:toggle_skip` — toggle skip_invoicing flag
    * `:generate_share_token` — generate or return existing share token
    * `:start_ksef_submission` — lock an issued invoice while it is sent to KSeF
    * `:record_ksef_submission` — record the KSeF session, invoice reference, checksum and storage date
    * `:confirm_in_ksef` — record the KSeF number of an accepted invoice
    * `:withdraw_ksef_submission` — unlock an invoice KSeF did not accept

  ## Generic Actions

    * `:preview_invoice` / `:preview_correction` — read-only validated document previews
    * `:cancel` — cancel a KSeF-submitted invoice via zero-quantity correction
    * `:get_next_number` — get next available invoice number for date/format/series
    * `:validate_number` — validate an invoice number (format, duplicate, gap)
    * `:list_series` — list distinct invoice number series

  ## Public functions


  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshEvents.Events, AshJido, AshOban],
    notifiers: [Ash.Notifier.PubSub]

  alias AshMoney.Types.Money
  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing, as: InvoicingDomain
  alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections
  alias Firmowid.Ash.Invoicing.Changes
  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Invoicing.SalesInvoice.Dispatchers.Communication
  alias Firmowid.Ash.Invoicing.SalesInvoice.Preview
  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceChain
  alias Firmowid.Ash.Invoicing.Signals
  alias Firmowid.Ash.Invoicing.Types.InvoiceInput
  alias Firmowid.Ash.Invoicing.Validations
  alias Firmowid.Ash.Invoicing.VatExemption
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query
  require Firmowid.Ash.Invoicing.SalesInvoice.EffectiveFields, as: EffectiveFields
  require Resource

  @eu_countries CountryCodes.eu_countries_with_aliases()
  # A draft is the complete invoice except for its number; issuance dates it today.
  @draft_fields Keyword.keys(InvoiceInput.subtype_constraints()[:fields]) --
                  [:sales_invoice_items, :invoice_number, :issue_date, :correction_reason]
  # An imported document arrives complete, with the seller and dates the other software issued,
  # and already locked like an invoice KSeF confirmed, so it also brings its denormalized item names.
  @ksef_import_fields (@draft_fields --
                         [:counterparty_id, :internal_note, :skip_invoicing, :should_send_emails]) ++
                        [
                          :invoice_number,
                          :issue_date,
                          :correction_reason,
                          :seller_nip,
                          :seller_display_name,
                          :seller_address,
                          :ksef_invoice_kind,
                          :ksef_number,
                          :ksef_invoice_checksum,
                          :ksef_permanent_storage_date,
                          :related_parties,
                          :receipt_invoice,
                          :locked_at,
                          :item_names
                        ]

  postgres do
    table "sales_invoices"
    repo Firmowid.Repo
  end

  events do
    event_log Firmowid.Ash.Events.Event
    only_actions [:connect_transactions, :disconnect_transactions, :disconnect_all_transactions]
  end

  jido do
    action :list,
      name: "list_sales_invoices",
      description: "Listuje faktury sprzedażowe z bezpiecznymi filtrami Ash.",
      category: "ash.invoicing.read",
      tags: ["assistant", "sales_invoice"]

    action :by_id,
      name: "get_sales_invoice_by_id",
      description: "Pobiera fakturę sprzedażową po identyfikatorze.",
      category: "ash.invoicing.read",
      tags: ["assistant", "sales_invoice"]

    action :connect_transactions,
      name: "connect_sales_invoice_transactions",
      description: "Łączy fakturę sprzedażową z podanymi transakcjami.",
      category: "ash.invoicing.write",
      tags: ["assistant", "sales_invoice", "matching"]
  end

  oban do
    scheduled_actions do
      schedule :dispatch_overdue_sales_invoice_reminders, "15 7 * * *" do
        action :dispatch_overdue_sales_invoice_reminders
        queue :invoicing
        list_tenants {Firmowid.Ash.Invoicing.SalesInvoice.OrganizationTenantList, []}

        worker_module_name Firmowid.Ash.Invoicing.SalesInvoice.Worker.DispatchOverdueSalesInvoiceReminders
      end
    end
  end

  code_interface do
    # Reads
    define :by_id, args: [:id], action: :by_id
    define :get, args: [:id], action: :by_id
    define :read, action: :read
    define :list, action: :list
    define :by_share_token, args: [:token]

    define :public_shared_chain,
      action: :public_shared_chain,
      args: [:root_invoice_id, :root_share_token]

    # Writes
    define :draft, action: :draft
    define :issue, action: :issue
    define :correct, action: :correct
    define :import_from_ksef, action: :import_from_ksef
    define :revise, action: :revise
    define :finalize, action: :finalize
    define :return_to_draft, action: :return_to_draft
    define :preview_invoice, action: :preview_invoice
    define :preview_correction, action: :preview_correction

    define :attach_suggested_counterparty,
      args: [:counterparty_id],
      action: :attach_suggested_counterparty

    define :destroy, action: :destroy
    define :cancel, args: [:invoice_id], action: :cancel
    define :toggle_skip, action: :toggle_skip
    define :generate_share_token, action: :generate_share_token
    define :match_pending_invoices, args: [:signal]
    define :dispatch_ksef_confirmation, args: [:signal]
    define :start_ksef_submission, action: :start_ksef_submission
    define :record_ksef_submission, action: :record_ksef_submission
    define :confirm_in_ksef, action: :confirm_in_ksef
    define :withdraw_ksef_submission, action: :withdraw_ksef_submission
    define :denormalize_item_names, action: :denormalize_item_names

    # Invoice numbering
    define :get_next_number, args: [:date, {:optional, :series}, {:optional, :omit_invoice_id}]
    define :validate_number, args: [:invoice_number, :issue_date, {:optional, :omit_invoice_id}]
    define :list_series, args: []

    define :dispatch_overdue_sales_invoice_reminders,
      action: :dispatch_overdue_sales_invoice_reminders
  end

  actions do
    defaults [:read]

    read :list do
      description "List sales invoices with search, status, and reconciliation filters."

      pagination do
        required? false
        keyset? true
        max_page_size 100
      end

      argument :date_from, :date
      argument :date_to, :date
      argument :query, :string, constraints: [max_length: 500]
      argument :currency, :string
      argument :amount_gt, :decimal
      argument :amount_lt, :decimal

      argument :date_field, :atom do
        constraints one_of: [:issue_date, :sale_date, :due_date, :any]
        default :issue_date
      end

      argument :kind, :atom do
        constraints one_of: [:vat, :kor]
      end

      argument :reconciliation, :atom do
        constraints one_of: [:pending, :matched, :skipped]
      end

      argument :submission, :atom do
        constraints one_of: [:draft, :confirmed]
      end

      argument :ids, {:array, :uuid_v7}
      argument :inserted_from, :utc_datetime
      argument :inserted_to, :utc_datetime
      argument :buyer_type, :atom, constraints: [one_of: [:company, :individual]]
      argument :is_cash, :boolean
      argument :is_reverse_charge, :boolean

      argument :limit, :integer do
        constraints min: 1
      end

      argument :listing_sort, :atom, constraints: [one_of: [:newest, :oldest]]

      validate compare(:date_to, greater_than_or_equal_to: :date_from),
        where: [present(:date_from), present(:date_to)],
        message: "Must be on or after date_from"

      prepare fn query, _context ->
        case Ash.Query.get_argument(query, :currency) do
          nil -> query
          currency -> Ash.Query.set_argument(query, :currency, String.upcase(currency))
        end
      end

      validate one_of(:currency, Enum.map(Elixir.Money.known_currencies(), &to_string/1)),
        message: "Must be a recognized currency code"

      # Date filtering — conditional on date_field
      prepare {Firmowid.Ash.Invoicing.Preparations.FilterByDateField, []}

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
               columns:
                 ~w(buyer_full_name buyer_given_name buyer_surname invoice_number buyer_email buyer_description buyer_id item_names)a}

      # Kind filter
      prepare build(filter: expr(ksef_invoice_kind == ^arg(:kind))) do
        where present(:kind)
      end

      prepare build(filter: expr(amount[:currency] == ^arg(:currency))) do
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

      # :draft — no invoice_number assigned yet
      prepare build(filter: expr(is_nil(invoice_number))) do
        where argument_equals(:submission, :draft)
      end

      # :confirmed — has invoice_number
      prepare build(filter: expr(not is_nil(invoice_number))) do
        where argument_equals(:submission, :confirmed)
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

      prepare build(filter: expr(buyer_type == ^arg(:buyer_type))) do
        where present(:buyer_type)
      end

      prepare build(filter: expr(is_cash_account == true)) do
        where argument_equals(:is_cash, true)
      end

      prepare build(filter: expr(is_reverse_charge == true)) do
        where argument_equals(:is_reverse_charge, true)
      end

      prepare build(sort: [issue_date: :desc]) do
        where absent(:query)
      end

      prepare build(limit: arg(:limit)) do
        where present(:limit)
      end

      prepare Firmowid.Ash.Invoicing.Preparations.SortInvoiceListing
    end

    read :by_id do
      description "Fetch a sales invoice by ID."
      get_by [:id]
    end

    read :public_shared_chain do
      description "Fetch the root shared invoice and its corrections authorized by the root share token."

      argument :root_invoice_id, :uuid_v7, allow_nil?: false
      argument :root_share_token, :string, allow_nil?: false

      filter expr(
               (id == ^arg(:root_invoice_id) and share_token == ^arg(:root_share_token)) or
                 (corrected_invoice_id == ^arg(:root_invoice_id) and
                    corrected_invoice.share_token == ^arg(:root_share_token))
             )
    end

    action :by_share_token, :struct do
      description "Fetch the shared root invoice and its correction chain by public share token."
      constraints instance_of: __MODULE__
      allow_nil? true
      argument :token, :string, allow_nil?: false

      run fn input, context ->
        # Justified Ecto exception: cross-tenant lookup by share token.
        # Ash multitenancy requires tenant to be set before querying, but here
        # we don't know the tenant until we find the invoice. The initial lookup
        # uses Repo.one(skip_organization_id: true) to discover the org_id,
        # then the full read uses the standard :by_id action with proper tenant.
        import Ecto.Query

        share_token = input.arguments.token
        opts = Ash.Context.to_opts(context)

        root_invoice_row =
          __MODULE__
          |> where([i], i.share_token == ^share_token and i.ksef_invoice_kind == :vat)
          |> select([i], {i.id, i.organization_id})
          |> Firmowid.Repo.one(skip_organization_id: true)

        case root_invoice_row do
          nil ->
            {:ok, nil}

          {root_invoice_id, org_id} ->
            read_opts =
              opts
              |> Keyword.delete(:tenant)
              |> Keyword.put(:tenant, org_id)

            chain =
              SalesInvoiceChain.fetch_public_shared_chain!(
                root_invoice_id,
                share_token,
                read_opts
              )

            {:ok, List.first(chain)}
        end
      end
    end

    # -- Write actions ---------------------------------------------------------

    create :draft do
      description "Save a complete VAT invoice without a number. Finalizing it later dates it that day."
      primary? true
      accept @draft_fields
      argument :input, InvoiceInput
      argument :sales_invoice_items, {:array, :map}
      argument :confirmation_id, :uuid_v7, public?: false

      change Changes.ApplyInvoiceInput

      change set_attribute(:id, arg(:confirmation_id)) do
        where present(:confirmation_id)
      end

      change Changes.PrepareInvoiceSeller
      change Changes.PrepareInvoiceItems

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)
      change Changes.SetItemNames
      change Changes.SetIsCashAccount
      change {Changes.ValidateCountryCode, field: :buyer_country}
      change Changes.BindInvoiceCounterparty

      validate Validations.CompleteInvoice

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    create :issue do
      description "Issue a new invoice dated today and queue its KSeF submission in the same transaction."
      accept [:invoice_number | @draft_fields]
      argument :input, InvoiceInput
      argument :sales_invoice_items, {:array, :map}
      argument :confirmation_id, :uuid_v7

      change Changes.ApplyInvoiceInput

      change set_attribute(:id, arg(:confirmation_id)) do
        where present(:confirmation_id)
      end

      change Changes.PrepareInvoiceSeller
      change Changes.PrepareInvoiceItems

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)
      change Changes.SetItemNames
      change Changes.SetIsCashAccount
      change {Changes.ValidateCountryCode, field: :buyer_country}
      change Changes.BindInvoiceCounterparty
      # Last, so the submission job is queued only after every other write of this transaction.
      change Changes.SubmitIssuedInvoice

      validate Validations.InvoiceNumberRequired
      validate Validations.CompleteInvoice

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    create :correct do
      description "Issue a correction of an issued invoice and queue its KSeF submission in the same transaction."

      accept [
        :invoice_number,
        :issue_date,
        :sale_date,
        :due_date,
        :correction_reason,
        :payment_method,
        :currency,
        :seller_account_number,
        :vat_exemption_type,
        :vat_exemption_basis,
        :buyer_type,
        :buyer_id,
        :buyer_full_name,
        :buyer_given_name,
        :buyer_surname,
        :buyer_pesel,
        :buyer_display_name,
        :buyer_address,
        :buyer_country,
        :buyer_email,
        :buyer_phone,
        :buyer_description,
        :should_send_emails,
        :is_reverse_charge
      ]

      argument :original_invoice_id, :uuid_v7, allow_nil?: false
      argument :sales_invoice_items, {:array, :map}
      argument :input, InvoiceInput
      argument :confirmation_id, :uuid_v7
      argument :preview?, :boolean, default: false, public?: false

      change Changes.ApplyInvoiceInput
      change set_new_attribute(:issue_date, &Date.utc_today/0)

      change set_attribute(:id, arg(:confirmation_id)) do
        where present(:confirmation_id)
      end

      change {Changes.PrepareCorrection, []}
      change Changes.InheritItemGtu
      change Changes.PrepareInvoiceItems

      # An imported invoice's own rates and cash accounting stay unless the correction changes them.
      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items} do
        where Validations.CorrectedRatesNormalized
      end

      change manage_relationship(:sales_invoice_items, type: :direct_control)
      change Changes.SetItemNames

      change Changes.SetIsCashAccount do
        where {Validations.DiffersFromCorrectedState, field: :payment_method}
      end

      change {Changes.ValidateCountryCode, field: :buyer_country}

      # Last, so the submission job is queued only after every other write of this transaction.
      change Changes.SubmitIssuedInvoice do
        where argument_equals(:preview?, false)
      end

      validate present(:invoice_number) do
        where argument_equals(:preview?, false)
        message "Pole jest wymagane"
      end

      validate string_length(:correction_reason, max: 256),
        message: "Powód korekty może mieć maksymalnie 256 znaków"

      validate Validations.CompleteInvoice

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    create :import_from_ksef do
      description "Record an invoice issued outside Firmowid that KSeF already stores."
      accept @ksef_import_fields
      argument :sales_invoice_items, {:array, :map}, allow_nil?: false
      argument :corrected_invoice_ksef_number, :string
      argument :corrected_lines, {:array, :map}
      argument :ksef_gross_total, :decimal, allow_nil?: false
      argument :ksef_vat, :map, allow_nil?: false

      change Changes.LinkCorrectedKsefInvoice
      # The document's own VAT rates are kept, so no reverse-charge normalization here.
      change Changes.PrepareInvoiceItems
      change manage_relationship(:sales_invoice_items, type: :direct_control)
      change {Changes.ValidateCountryCode, field: :buyer_country}
      change Changes.BindInvoiceCounterparty
      # Last, to compare the saved invoice and its items with the KSeF document.
      change Changes.VerifyImportedDocument

      validate Validations.CompleteInvoice

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}
    end

    update :revise do
      description "Revise a saved, unnumbered VAT invoice draft."
      primary? true
      require_atomic? false
      accept @draft_fields -- [:skip_invoicing]
      argument :input, InvoiceInput
      argument :sales_invoice_items, {:array, :map}

      change Changes.ApplyInvoiceInput
      change filter(expr(is_nil(invoice_number) and ksef_invoice_kind == :vat))
      change Changes.PrepareInvoiceSeller
      change Changes.PrepareInvoiceItems

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)
      change Changes.SetItemNames
      change Changes.SetIsCashAccount
      change {Changes.ValidateCountryCode, field: :buyer_country}
      change Changes.BindInvoiceCounterparty

      validate Validations.InvoiceDraft
      validate {Validations.CheckIfLocked, []}, always_atomic?: true
      validate Validations.CompleteInvoice

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    update :finalize do
      description "Number a draft, date it today and queue its KSeF submission in the same transaction."
      require_atomic? false
      accept [:invoice_number | @draft_fields -- [:skip_invoicing]]
      argument :input, InvoiceInput
      argument :sales_invoice_items, {:array, :map}

      change Changes.ApplyInvoiceInput
      change filter(expr(is_nil(invoice_number) and ksef_invoice_kind == :vat))
      change Changes.PrepareInvoiceSeller
      change Changes.PrepareInvoiceItems

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)
      change Changes.SetItemNames
      change Changes.SetIsCashAccount
      change {Changes.ValidateCountryCode, field: :buyer_country}
      change Changes.BindInvoiceCounterparty
      # Last, so the submission job is queued only after every other write of this transaction.
      change Changes.SubmitIssuedInvoice

      validate Validations.InvoiceDraft
      validate Validations.InvoiceNumberRequired
      validate {Validations.CheckIfLocked, []}, always_atomic?: true
      validate Validations.CompleteInvoice

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    update :return_to_draft do
      description "Withdraw a VAT invoice that KSeF did not accept back to an unnumbered draft."
      public? false
      require_atomic? false
      accept []

      change filter(expr(is_nil(ksef_number) and ksef_invoice_kind == :vat))
      change set_attribute(:invoice_number, nil)
      change set_attribute(:locked_at, nil)
      change set_attribute(:ksef_invoice_checksum, nil)
    end

    update :attach_suggested_counterparty do
      description "Attach an unassigned invoice to a currently suggested counterparty without changing its issued buyer data, including when locked for KSeF."
      require_atomic? false
      accept []

      argument :counterparty_id, :uuid_v7, allow_nil?: false

      # Enforce suggestion eligibility atomically at write time.
      change filter(
               expr(
                 is_nil(counterparty_id) and
                   exists(
                     Counterparty,
                     id == ^arg(:counterparty_id) and
                       type == parent(buyer_type) and
                       country == parent(buyer_country) and
                       ((not is_nil(pesel) and
                           pesel != "" and
                           not is_nil(parent(buyer_pesel)) and
                           parent(buyer_pesel) != "" and
                           fragment(
                             "regexp_replace(coalesce(?, ''), '\\D', '', 'g')",
                             parent(buyer_pesel)
                           ) ==
                             fragment("regexp_replace(coalesce(?, ''), '\\D', '', 'g')", pesel)) or
                          ((is_nil(pesel) or pesel == "") and
                             not is_nil(tax_id) and
                             tax_id != "" and
                             not is_nil(parent(buyer_id)) and
                             parent(buyer_id) != "" and
                             fragment(
                               "regexp_replace(upper(coalesce(?, '')), '[^0-9A-Z]', '', 'g')",
                               parent(buyer_id)
                             ) ==
                               fragment(
                                 "regexp_replace(upper(coalesce(?, '')), '[^0-9A-Z]', '', 'g')",
                                 tax_id
                               )))
                   )
               )
             )

      change {Changes.AttachSuggestedCounterparty, []}
    end

    destroy :destroy do
      description "Delete a sales invoice when deletion is allowed."
      require_atomic? false

      validate {Validations.CheckIfLocked, []}, always_atomic?: true

      validate absent(:ksef_number) do
        always_atomic? true
        message "KSeF-submitted invoices cannot be deleted"
      end
    end

    update :toggle_skip do
      description "Toggle whether this sales invoice is skipped during matching workflows."
      require_atomic? false
      accept []

      change fn changeset, _context ->
        current = Ash.Changeset.get_data(changeset, :skip_invoicing)
        Ash.Changeset.force_change_attribute(changeset, :skip_invoicing, !current)
      end
    end

    update :generate_share_token do
      description "Generate or return the public share token for this sales invoice."
      require_atomic? false
      accept []
      change {Changes.GenerateShareToken, []}
    end

    update :denormalize_item_names do
      description "Internal action to update the denormalized item_names field. Used by SetItemNames change to avoid recursion."
      require_atomic? false
      accept [:item_names]

      validate {Validations.CheckIfLocked, []}, always_atomic?: true
    end

    update :start_ksef_submission do
      description "Lock an issued invoice while it is sent to KSeF, forgetting any previous attempt."
      require_atomic? false
      accept []
      change set_attribute(:locked_at, &DateTime.utc_now/0)
      change set_attribute(:ksef_session_reference_number, nil)
      change set_attribute(:ksef_invoice_checksum, nil)
    end

    update :record_ksef_submission do
      description "Record what KSeF reported about the invoice: its session, invoice reference or checksum and storage date."
      require_atomic? false

      accept [
        :ksef_session_reference_number,
        :ksef_invoice_checksum,
        :ksef_permanent_storage_date
      ]
    end

    update :confirm_in_ksef do
      description "Record the KSeF number and checksum KSeF assigned to the accepted invoice."
      require_atomic? false
      accept [:ksef_number, :ksef_invoice_checksum]

      validate present(:ksef_number)

      emit Signals, :sales_invoice_confirmed_in_ksef,
        fields: [sales_invoice_id: :id],
        where: [changing(:ksef_number)]
    end

    update :withdraw_ksef_submission do
      description "Unlock an invoice KSeF did not accept, keeping the session of the last attempt."
      require_atomic? false
      accept []
      change set_attribute(:ksef_number, nil)
      change set_attribute(:locked_at, nil)
      change set_attribute(:ksef_invoice_checksum, nil)
    end

    # -- Generic actions -------------------------------------------------------

    # TODO: Extract the ~100-line inline `run fn` below into a named module
    # implementing `Ash.Resource.Actions.Implementation` (e.g. Actions.CancelInvoice).
    action :cancel, :struct do
      description "Cancel a KSeF-submitted VAT invoice by creating a zero-value correction."
      constraints instance_of: __MODULE__
      argument :invoice_id, :uuid_v7, allow_nil?: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        correction_snapshot_load = [
          :sales_invoice_items,
          :sale_date,
          :due_date,
          :invoice_type,
          :seller_nip,
          :seller_display_name,
          :seller_address,
          :seller_name,
          :seller_surname,
          :seller_account_number,
          :counterparty_id,
          :buyer_type,
          :buyer_id,
          :buyer_full_name,
          :buyer_given_name,
          :buyer_surname,
          :buyer_display_name,
          :buyer_address,
          :buyer_country,
          :buyer_is_different_mail_address,
          :buyer_mail_address,
          :buyer_mail_country,
          :buyer_email,
          :buyer_phone,
          :buyer_description,
          :buyer_pesel,
          :payment_method,
          :currency,
          :is_reverse_charge,
          :is_cash_account
        ]

        invoice =
          __MODULE__
          |> Ash.get!(input.arguments.invoice_id, opts)
          |> Ash.load!([:effective_snapshot], opts)

        if invoice.ksef_invoice_kind == :vat and invoice.ksef_number != nil do
          latest = Ash.load!(invoice.effective_snapshot, correction_snapshot_load, opts)

          issue_date = Date.utc_today()

          # Get next FK-series number
          {:ok, invoice_number} =
            issue_date
            |> __MODULE__.input_to_get_next_number("FK", nil, opts)
            |> Ash.run_action(opts)

          zeroed_items =
            Enum.map(latest.sales_invoice_items, fn item ->
              item
              |> Map.take([:index, :name, :unit, :unit_price, :vat_rate, :gtu])
              |> Map.put(:quantity, Decimal.new(0))
            end)

          correction_reason =
            case latest.invoice_type do
              :foreign -> "Anulowanie faktury / Invoice cancellation"
              _poland -> "Anulowanie faktury"
            end

          Ash.create(
            __MODULE__,
            %{
              original_invoice_id: invoice.id,
              invoice_number: invoice_number,
              issue_date: issue_date,
              sale_date: latest.sale_date,
              due_date: latest.due_date,
              correction_reason: correction_reason,
              sales_invoice_items: zeroed_items
            },
            Keyword.put(opts, :action, :correct)
          )
        else
          {:error, "can only cancel KSeF-submitted VAT invoices"}
        end
      end
    end

    action :preview_invoice, :struct do
      description "Validate and calculate an invoice without saving it."
      constraints instance_of: __MODULE__
      argument :input, InvoiceInput, allow_nil?: false
      argument :invoice_id, :uuid_v7

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        case input.arguments[:invoice_id] do
          nil ->
            %{input: input.arguments.input}
            |> __MODULE__.changeset_to_draft(opts)
            |> Preview.from_changeset(opts)

          id ->
            with {:ok, invoice} <-
                   __MODULE__.by_id(
                     id,
                     Keyword.merge(opts,
                       not_found_error?: true,
                       load: [:sales_invoice_items, :reference_invoice, :corrected_invoice]
                     )
                   ) do
              invoice
              |> __MODULE__.changeset_to_revise(%{input: input.arguments.input}, opts)
              |> Preview.from_changeset(opts)
            end
        end
      end
    end

    action :preview_correction, :struct do
      description "Validate and calculate a correction without saving it."
      constraints instance_of: __MODULE__
      argument :input, InvoiceInput, allow_nil?: false
      argument :original_invoice_id, :uuid_v7, allow_nil?: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        input.arguments
        |> __MODULE__.changeset_to_correct(Keyword.put(opts, :private_arguments, %{preview?: true}))
        |> Preview.from_changeset(opts)
      end
    end

    action :get_next_number, :string do
      description "Return the next available invoice number for a date, numbering format and optional series."
      argument :date, :date, allow_nil?: false
      argument :series, :string
      argument :omit_invoice_id, :uuid

      argument :format, :atom,
        allow_nil?: false,
        default: :monthly,
        constraints: [one_of: [:monthly, :yearly]]

      run fn input, context ->
        %{date: date, format: format} = input.arguments
        series = input.arguments[:series]
        omit_invoice_id = input.arguments[:omit_invoice_id]
        opts = Ash.Context.to_opts(context)

        starting_num =
          format
          |> read_invoice_numbers_matching(date, series, omit_invoice_id, opts)
          |> Enum.map(&parse_invoice_number/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, %{num: num}} -> num end)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, find_free_invoice_number(starting_num, format, date, series, omit_invoice_id, opts)}
      end
    end

    action :validate_number, {:array, :term} do
      description "Validate an invoice number and return any warnings about format, duplicates, or gaps."
      argument :invoice_number, :string, allow_nil?: false
      argument :issue_date, :date, allow_nil?: false
      argument :omit_invoice_id, :uuid

      run fn input, context ->
        invoice_number = input.arguments.invoice_number
        issue_date = input.arguments.issue_date
        omit_invoice_id = input.arguments[:omit_invoice_id]
        opts = Ash.Context.to_opts(context)

        all_suggestions =
          issue_date
          |> InvoicingDomain.get_next_numbers_for_series(opts,
            omit_invoice_id: omit_invoice_id
          )
          |> Enum.sort()
          |> Enum.map(fn {_format_and_series, number} -> number end)

        parsed = parse_invoice_number(invoice_number)

        # TODO: Refactor sequential `warnings` accumulation into a pipeline
        # or a list of check functions to reduce mutable-style reassignments.
        warnings = []

        warnings =
          if parsed == :error do
            [{:invalid_format, all_suggestions} | warnings]
          else
            warnings
          end

        warnings =
          if invoice_number_exists?(invoice_number, omit_invoice_id, opts) do
            [{:duplicate, all_suggestions} | warnings]
          else
            warnings
          end

        warnings =
          case parsed do
            {:ok, %{num: current_num, format: parsed_format, series: parsed_series}} ->
              {:ok, expected} =
                __MODULE__.get_next_number(
                  issue_date,
                  parsed_series,
                  omit_invoice_id,
                  %{format: parsed_format},
                  opts
                )

              case parse_invoice_number(expected) do
                {:ok, %{num: expected_num}} when current_num > expected_num ->
                  [{:gap, expected} | warnings]

                _ ->
                  warnings
              end

            :error ->
              warnings
          end

        {:ok, Enum.reverse(warnings)}
      end
    end

    action :list_series, {:array, :string} do
      description "List all detected invoice number series visible in the current scope."

      run fn _input, context ->
        opts = Ash.Context.to_opts(context)

        result =
          opts
          |> read_all_invoice_numbers()
          |> Enum.map(&parse_invoice_number/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, %{series: s}} -> s end)
          |> Enum.uniq()
          |> Enum.sort_by(fn
            nil -> ""
            s -> s
          end)

        {:ok, result}
      end
    end

    action :dispatch_overdue_sales_invoice_reminders, :integer do
      description "Scan overdue sales invoices and enqueue payment reminder emails for eligible invoices."
      run __MODULE__.Scanners.OverdueReminders
    end

    update :connect_transactions do
      description "Connect transactions to this sales invoice via the join table."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      change Changes.RequireTransactionIds
      change Changes.ValidateTransactionAvailability
      change manage_relationship(:transaction_ids, :transactions, type: :append)
    end

    update :disconnect_transactions do
      description "Disconnect the provided transactions from this sales invoice."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      change Changes.RequireTransactionIds
      change manage_relationship(:transaction_ids, :transactions, type: :remove)
    end

    update :disconnect_all_transactions do
      description "Disconnect all transactions from this sales invoice."
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.manage_relationship(changeset, :transactions, [], on_missing: :unrelate)
      end
    end

    action :dispatch_ksef_confirmation do
      description "Sends the confirmation of an invoice accepted by KSeF to the buyer."
      argument :signal, Signals.SalesInvoiceConfirmedInKsef, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        scope = %Scope{
          actor: %SystemActor{org_id: signal.organization_id, role: :sales_invoice_processor},
          tenant: signal.organization_id
        }

        with {:ok, invoice} <-
               InvoicingDomain.get_sales_invoice(signal.sales_invoice_id, scope: scope),
             {:ok, _result} <- Communication.dispatch(invoice, :ksef_confirmed, scope) do
          :ok
        end
      end
    end

    action :match_pending_invoices do
      description "Matches pending sales invoices after a bank account sync."
      argument :signal, Finances.Signals.BankAccountSynced, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        signal.organization_id
        |> InvoiceMatching.matcher_scope()
        |> InvoiceMatching.match_sales_invoices()
      end
    end
  end

  policies do
    policy_group always() do
      policy action(:match_pending_invoices) do
        authorize_if signal_in(Finances.Signals, :bank_account_synced)
      end

      policy action(:dispatch_ksef_confirmation) do
        authorize_if signal_in(Signals, :sales_invoice_confirmed_in_ksef)
      end

      policy {SystemActorRole, roles: [:sales_invoice_processor]} do
        authorize_if always()
      end

      policy AshObanInteraction do
        authorize_if action([
                       :dispatch_overdue_sales_invoice_reminders,
                       :match_pending_invoices,
                       :dispatch_ksef_confirmation
                     ])
      end

      policy {SystemActorRole, roles: [:analysis_reader]} do
        authorize_if action_type(:read)
      end

      policy {SystemActorRole, roles: [:invoice_matcher]} do
        authorize_if action([
                       :connect_transactions,
                       :disconnect_transactions,
                       :disconnect_all_transactions
                     ])

        authorize_if action_type(:read)
      end

      policy {SystemActorRole, roles: [:ksef_session]} do
        authorize_if action([
                       :start_ksef_submission,
                       :record_ksef_submission,
                       :confirm_in_ksef,
                       :withdraw_ksef_submission
                     ])
      end

      policy {SystemActorRole, roles: [:anonymous]} do
        authorize_if action([:by_share_token, :public_shared_chain])
      end
    end

    policy_group {AtLeastRole, role: :invoicing} do
      policy action_type(:read) do
        authorize_if always()
      end

      policy action_type([:create, :update, :destroy, :action]) do
        authorize_if action([
                       :connect_transactions,
                       :disconnect_transactions,
                       :disconnect_all_transactions
                     ])

        authorize_if {AtLeastRole, role: :accountant}
      end

      # Only the KSeF import may record invoices KSeF stores; a user could otherwise fabricate one.
      policy action(:import_from_ksef) do
        forbid_if always()
      end

      # Only system actors/AshOban may run scheduled reminder scans - users have no UI for this.
      policy action(:dispatch_overdue_sales_invoice_reminders) do
        forbid_if always()
      end
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "sales_invoice"

    publish :draft, ["created", :_tenant]
    publish :issue, ["created", :_tenant]
    publish :correct, ["created", :_tenant]
    publish :import_from_ksef, ["created", :_tenant]
    publish :revise, ["updated", :_tenant]
    publish :finalize, ["updated", :_tenant]
    publish :return_to_draft, ["updated", :_tenant]
    publish :destroy, ["destroyed", :_tenant]
    publish :toggle_skip, ["updated", :_tenant]
    publish :generate_share_token, ["updated", :_tenant]
    publish :attach_suggested_counterparty, ["updated", :_tenant]
    publish :connect_transactions, ["updated", :_tenant]
    publish :disconnect_transactions, ["updated", :_tenant]
    publish :disconnect_all_transactions, ["updated", :_tenant]
  end

  changes do
    change {Changes.ClearVatExemptionBasis, []}
  end

  validations do
    validate present(:vat_exemption_basis) do
      where attribute_equals(:vat_exemption_type, :other)
      message "Podaj podstawę prawną zwolnienia z VAT."
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

    # Stored (not a calculation) because two independent change hooks collaborate
    # to maintain it: SetIsCashAccount (payment_method == :cash) and
    # CastBasedOnInvoiceType (forces false for foreign invoices). A calculation
    # would need to encode both rules and complicate the snapshot system.
    attribute :is_cash_account, :boolean, default: false, public?: true
    attribute :is_reverse_charge, :boolean, default: false, public?: true
    # KSeF markers: a transaction between related parties (TP) and an invoice for a receipt (FP).
    attribute :related_parties, :boolean, default: false, public?: true
    attribute :receipt_invoice, :boolean, default: false, public?: true

    attribute :skip_invoicing, :boolean, default: false, public?: true
    attribute :should_send_emails, :boolean, default: false, public?: true

    attribute :item_names, :string, public?: true

    attribute :share_token, :string, public?: true

    # KSeF submission tracking
    attribute :ksef_number, :string, public?: true
    attribute :ksef_session_reference_number, :string, public?: true
    attribute :ksef_invoice_checksum, :string, public?: true
    attribute :locked_at, :utc_datetime, public?: true
    # When KSeF permanently stored the invoice; the latest one is where the next import starts.
    attribute :ksef_permanent_storage_date, :naive_datetime, public?: true

    # KSeF FA(3) fields
    attribute :ksef_invoice_kind, :atom,
      constraints: [one_of: [:vat, :kor]],
      default: :vat,
      public?: true

    attribute :correction_reason, :string, public?: true
    # Public note visible on invoice/PDF and sent to KSeF (StopkaFaktury)
    attribute :invoice_note, :string, public?: true
    # Internal-only note, visible inside Firmowid only. Max 10_000 chars.
    attribute :internal_note, :string, public?: false
    # Validate internal_note length (DB will allow large text but enforce here)
    # Use an action-level validation instead of a bare validate/1 call inside attributes

    attribute :vat_exemption_type, :atom,
      public?: true,
      allow_nil?: true,
      constraints: [one_of: VatExemption.valid_types()]

    attribute :vat_exemption_basis, :string,
      public?: true,
      allow_nil?: true,
      constraints: [max_length: 256, trim?: true, allow_empty?: false]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :counterparty, Counterparty do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :corrected_invoice, __MODULE__ do
      allow_nil? true
      attribute_writable? true
    end

    has_many :corrections, __MODULE__ do
      source_attribute :id
      destination_attribute :corrected_invoice_id
      sort locked_at: :asc_nils_last, inserted_at: :asc
    end

    has_one :latest_correction, __MODULE__ do
      destination_attribute :corrected_invoice_id
      sort locked_at: :desc_nils_last, inserted_at: :desc
    end

    has_many :sales_invoice_items, SalesInvoiceItem do
      sort index: :asc
    end

    has_many :email_deliveries, SalesInvoiceEmailDelivery do
      source_attribute :id
      destination_attribute :sales_invoice_id
    end

    many_to_many :transactions, Firmowid.Ash.Finances.Transaction do
      through SalesInvoiceTransaction
      source_attribute_on_join_resource :sales_invoice_id
      destination_attribute_on_join_resource :transaction_id
    end

    has_many :entity_tags, Firmowid.Ash.Analysis.EntityTag do
      relationship_context %{data_layer: %{table: "sales_invoice_entity_tags"}}
      source_attribute :id
      destination_attribute :resource_id
    end
  end

  signals_in do
    from Signals do
      on :sales_invoice_confirmed_in_ksef, :dispatch_ksef_confirmation,
        delivery: {AshOban.Signals, queue: :sales_invoice_emails, max_attempts: 3}
    end

    from Finances.Signals do
      on :bank_account_synced, :match_pending_invoices,
        delivery:
          {AshOban.Signals,
           queue: :invoicing, unique: [keys: [:organization_id], states: [:available, :scheduled, :retryable]]}
    end
  end

  calculations do
    EffectiveFields.effective_correction_calculations()

    calculate :amount,
              Money,
              expr(
                if is_nil(currency) do
                  nil
                else
                  composite_type(
                    %{
                      currency: currency,
                      amount: if(is_nil(gross_value), do: 0, else: gross_value)
                    },
                    Money
                  )
                end
              )

    calculate :effective_amount,
              Money,
              expr(
                if exists(latest_correction, true) do
                  ^ref([:latest_correction], :amount)
                else
                  amount
                end
              )

    calculate :invoice_source,
              :string,
              expr(
                cond do
                  not is_nil(ksef_number) ->
                    "ksef"

                  not is_nil(ksef_session_reference_number) ->
                    "ksef"

                  is_nil(invoice_number) ->
                    "draft"

                  true ->
                    "document"
                end
              )

    calculate :effective_items,
              {:array, :struct},
              Firmowid.Ash.Invoicing.Calculations.EffectiveItems

    # net_value, vat_value, gross_value moved to aggregates (sum over expression calcs on items)

    calculate :effective_snapshot,
              :struct,
              Firmowid.Ash.Invoicing.Calculations.EffectiveSnapshot do
      description "Latest correction if exists, otherwise self."
      constraints instance_of: __MODULE__
    end

    calculate :reference_invoice, :struct, Firmowid.Ash.Invoicing.Calculations.ReferenceInvoice do
      constraints instance_of: __MODULE__
    end

    calculate :annotated_corrections,
              {:array, :struct},
              AnnotatedCorrections do
      constraints items: [instance_of: __MODULE__]
    end

    # Boolean status calculations — DB-pushable, filterable, sortable
    calculate :is_draft, :boolean, expr(is_nil(invoice_number))
    calculate :is_confirmed, :boolean, expr(not is_nil(invoice_number))
    calculate :is_ksef_submitted, :boolean, expr(not is_nil(ksef_number))

    calculate :ksef_submission_status,
              :atom,
              Firmowid.Ash.Invoicing.Calculations.KsefSubmissionStatus do
      constraints one_of: [:not_submitted, :submitting, :submitted, :failed]
      public? true
    end

    calculate :is_deletable, :boolean, expr(is_nil(ksef_number) and is_nil(locked_at))

    calculate :reconciliation_status,
              :atom,
              expr(
                cond do
                  exists(transactions, true) ->
                    :matched

                  skip_invoicing == true ->
                    :skipped

                  true ->
                    :pending
                end
              ) do
      description "Invoice reconciliation state derived from linked transactions and skip flag."
      constraints one_of: [:pending, :matched, :skipped]
    end

    # NOTE: This expr() logic is intentionally duplicated across SalesInvoice,
    # WizardState, and Counterparty (as :tax_id_type) because Ash expr()
    # calculations run in the DB and cannot call Elixir functions.
    # Runtime equivalent: CountryCodes.tax_id_type/3
    calculate :buyer_id_type,
              :atom,
              expr(
                cond do
                  not is_nil(buyer_pesel) and buyer_pesel != "" ->
                    :no_id

                  buyer_type == :individual and buyer_country == "PL" ->
                    :no_id

                  buyer_country == "PL" ->
                    :nip

                  buyer_country in ^@eu_countries ->
                    :eu_vat

                  buyer_country == "US" ->
                    :optional_id

                  true ->
                    :other_id
                end
              ) do
      description "Tax ID type for the buyer based on country, PESEL, and buyer type."
    end

    calculate :is_editable, :boolean, Firmowid.Ash.Invoicing.Calculations.IsEditable do
      description "Whether the invoice can be edited. KOR: only if latest correction. VAT: only if no corrections exist."
    end

    # Display name calculation — DB-pushable version of buyer_display_name/1
    calculate :buyer_display_name_label,
              :string,
              expr(
                cond do
                  not is_nil(buyer_display_name) and buyer_display_name != "" ->
                    buyer_display_name

                  buyer_type == :company ->
                    buyer_full_name

                  true ->
                    buyer_given_name <> " " <> buyer_surname
                end
              )
  end

  aggregates do
    sum :net_value, :sales_invoice_items, :net_value
    sum :vat_value, :sales_invoice_items, :vat_value
    sum :gross_value, :sales_invoice_items, :gross_value
  end

  identities do
    identity :invoice_number_per_org, [:invoice_number, :organization_id],
      nils_distinct?: true,
      message: "numer faktury już istnieje dla tej organizacji"
  end

  # Invoice numbering helpers -------------------------------------------------

  @monthly_number_regex ~r/^(\d+)\/(\d+)\/(\d+)(?:\/(.+))?$/
  @yearly_number_regex ~r/^(?:([A-Z]+)\/)?(\d+)\/(\d{4})$/

  @doc """
  Parses an invoice number in one of the supported numbering formats:

    * monthly `NN/MM/YYYY[/SERIES]`, e.g. `01/10/2026` or `01/10/2026/A`,
    * yearly `[PREFIX/]N/YYYY`, e.g. `1/2026` or `BC/1/2026`, where `PREFIX`
      is uppercase ASCII letters (usually the organization initials).

  Returns the numbering `format` (`:monthly` or `:yearly`), counter, month
  (`nil` for yearly numbers), year and optional series (the suffix of a
  monthly number or the prefix of a yearly one), or `:error` for other input.
  """
  @spec parse_invoice_number(term()) ::
          {:ok,
           %{
             format: :monthly | :yearly,
             num: pos_integer(),
             month: pos_integer() | nil,
             year: pos_integer(),
             series: String.t() | nil
           }}
          | :error
  def parse_invoice_number(invoice_number) when is_binary(invoice_number) do
    case Regex.run(@monthly_number_regex, invoice_number) do
      [_, num, month, year | series] ->
        {:ok,
         %{
           format: :monthly,
           num: String.to_integer(num),
           month: String.to_integer(month),
           year: String.to_integer(year),
           series: List.first(series)
         }}

      nil ->
        parse_yearly_invoice_number(invoice_number)
    end
  end

  def parse_invoice_number(_), do: :error

  defp parse_yearly_invoice_number(invoice_number) do
    case Regex.run(@yearly_number_regex, invoice_number) do
      [_, prefix, num, year] ->
        {:ok,
         %{
           format: :yearly,
           num: String.to_integer(num),
           month: nil,
           year: String.to_integer(year),
           series: if(prefix != "", do: prefix)
         }}

      nil ->
        :error
    end
  end

  @doc """
  Formats an invoice number for a counter, numbering format, date and optional
  series: monthly as `NN/MM/YYYY[/SERIES]`, yearly as `[SERIES/]N/YYYY`.
  """
  @spec format_invoice_number(pos_integer(), :monthly | :yearly, Date.t(), String.t() | nil) ::
          String.t()
  def format_invoice_number(num, :monthly, date, series) do
    Enum.join(
      [pad_two(num), pad_two(date.month), date.year] ++ List.wrap(series),
      "/"
    )
  end

  def format_invoice_number(num, :yearly, date, series) do
    Enum.join(List.wrap(series) ++ [num, date.year], "/")
  end

  defp pad_two(number), do: String.pad_leading("#{number}", 2, "0")

  @legal_form_words ~w(
    SP SPOLKA Z OO O OGRANICZONA ODPOWIEDZIALNOSCIA SA AKCYJNA SK SKA SPK SJ JAWNA
    KOMANDYTOWA KOMANDYTOWO PARTNERSKA SPP SC CYWILNA
  )

  @doc """
  Derives uppercase ASCII initials from an organization name, used as the
  prefix of the `INITIALS/N/YYYY` yearly numbering.

  The name is split into words on whitespace and hyphens. Words that are a
  Polish legal form (`sp.`, `z`, `o.o.`, `spółka`, `ograniczoną`,
  `odpowiedzialnością`, `S.A.`, `sp.k.`, `sp.j.`, `s.c.`, …, compared without
  dots, diacritics and case) are skipped. The first letter of every remaining
  word is transliterated to ASCII and upcased; words starting with a
  non-letter contribute nothing. For example
  `"Bytecraft Collective spółka z ograniczoną odpowiedzialnością"` and
  `"Bytecraft Collective sp. z o.o."` both give `"BC"`. Returns `nil` when no
  letter remains.
  """
  @spec organization_initials(String.t()) :: String.t() | nil
  def organization_initials(name) do
    name
    |> AnyAscii.transliterate()
    |> IO.iodata_to_binary()
    |> String.upcase()
    |> String.split(~r/[\s\-]+/, trim: true)
    |> Enum.reject(&(String.replace(&1, ".", "") in @legal_form_words))
    |> Enum.map_join(&String.slice(&1, 0, 1))
    |> String.replace(~r/[^A-Z]/, "")
    |> case do
      "" -> nil
      initials -> initials
    end
  end

  defp build_series_pattern(:monthly, date, nil), do: "^\\d+/#{pad_two(date.month)}/#{date.year}$"

  defp build_series_pattern(:monthly, date, series),
    do: "^\\d+/#{pad_two(date.month)}/#{date.year}/#{Regex.escape(series)}$"

  defp build_series_pattern(:yearly, date, nil), do: "^\\d+/#{date.year}$"

  defp build_series_pattern(:yearly, date, series), do: "^#{Regex.escape(series)}/\\d+/#{date.year}$"

  defp find_free_invoice_number(num, format, date, series, omit_invoice_id, opts) do
    invoice_number = format_invoice_number(num, format, date, series)

    if invoice_number_exists?(invoice_number, omit_invoice_id, opts) do
      find_free_invoice_number(num + 1, format, date, series, omit_invoice_id, opts)
    else
      invoice_number
    end
  end

  defp invoice_number_exists?(invoice_number, omit_invoice_id, opts) do
    query = Ash.Query.filter(__MODULE__, invoice_number == ^invoice_number)

    query =
      if omit_invoice_id do
        Ash.Query.filter(query, id != ^omit_invoice_id)
      else
        query
      end

    Ash.exists?(query, opts)
  end

  # Reads all invoice numbers of one numbering format and series in the date's period.
  # Uses fragment("? ~ ?", ...) for Postgres regex — Ash has no native regex operator.
  # Same escape hatch pattern as ParadeDB `&&&`.
  defp read_invoice_numbers_matching(format, date, series, omit_invoice_id, opts) do
    series_pattern = build_series_pattern(format, date, series)

    query =
      __MODULE__
      |> Ash.Query.filter(not is_nil(invoice_number))
      |> Ash.Query.filter(fragment("? ~ ?", invoice_number, ^series_pattern))

    query =
      if omit_invoice_id do
        Ash.Query.filter(query, id != ^omit_invoice_id)
      else
        query
      end

    query
    |> then(&__MODULE__.list!(Keyword.put(opts, :query, &1)))
    |> Enum.map(& &1.invoice_number)
  end

  @doc """
  Returns all non-nil invoice numbers visible in the provided Ash context.
  """
  def read_all_invoice_numbers(opts) do
    __MODULE__
    |> Ash.Query.filter(not is_nil(invoice_number))
    |> then(&__MODULE__.list!(Keyword.put(opts, :query, &1)))
    |> Enum.map(& &1.invoice_number)
  end
end
