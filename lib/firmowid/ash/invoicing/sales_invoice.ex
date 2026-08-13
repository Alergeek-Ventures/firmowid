# credo:disable-for-this-file ExDNA.Credo
# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
# This resource centralizes invoice lifecycle, numbering, and KSeF behaviors; reducing
# duplication requires extracting multiple actions/helpers into shared modules across boundaries.
defmodule Firmowid.Ash.Invoicing.SalesInvoice do
  @moduledoc """
  Ash resource for sales invoices.

  TODO: at 1270 lines, consider extracting inline `cancel` (~100 lines),
  `confirm_from_draft` (~60 lines), and numbering helpers (~110 lines)
  into dedicated modules — similar to how `EffectiveFields` was extracted.

  ## Read Actions

    * `:read` — consolidated read with optional filters: `date_from`, `date_to`,
      `date_field` (`:issue_date` | `:sale_date` | `:due_date` | `:any`),
      `kind` (`:vat` | `:kor`), `status` (`:unmatched` | `:confirmed`), `ids`
    * `:by_id` — single record by ID, preloads items, transactions, corrections, corrected_invoice
    * `:by_share_token` — find by share token (cross-tenant)

  ## Write Actions

    * `:create` — full invoice creation (from wizard confirm or direct)
    * `:update` — update draft or confirmed invoice
    * `:create_correction` — create a correction invoice (KOR) for a VAT invoice
    * `:destroy` — delete invoice (only if not KSeF-submitted)
    * `:toggle_skip` — toggle skip_invoicing flag
    * `:generate_share_token` — generate or return existing share token
    * `:lock_for_ksef` / `:unlock_for_ksef` — KSeF submission lock management
    * `:update_ksef_fields` — update KSeF tracking fields

  ## Generic Actions

    * `:cancel` — cancel a KSeF-submitted invoice via zero-quantity correction
    * `:get_next_number` — get next available invoice number for date/series
    * `:validate_number` — validate an invoice number (format, duplicate, gap)
    * `:list_series` — list distinct invoice number series

  ## Public functions


  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshEvents.Events, AshJido, AshOban],
    notifiers: [Ash.Notifier.PubSub],
    primary_read_warning?: false

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Invoicing, as: InvoicingDomain
  alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections
  alias Firmowid.Ash.Invoicing.Changes
  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceChain
  alias Firmowid.Ash.Invoicing.Validations
  alias Firmowid.Ash.Resource

  require Ash.Query
  require Firmowid.Ash.Invoicing.SalesInvoice.EffectiveFields, as: EffectiveFields
  require Resource

  @eu_countries CountryCodes.eu_countries_with_aliases()

  postgres do
    table "sales_invoices"
    repo Firmowid.Repo
  end

  events do
    event_log Firmowid.Ash.Events.Event
    only_actions [:connect_transactions, :disconnect_transactions, :disconnect_all_transactions]
  end

  jido do
    action :read,
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
    define :by_share_token, args: [:token]

    define :public_shared_chain,
      action: :public_shared_chain,
      args: [:root_invoice_id, :root_share_token]

    # Writes
    define :create, action: :create
    define :update, action: :update

    define :attach_suggested_counterparty,
      args: [:counterparty_id],
      action: :attach_suggested_counterparty

    define :destroy, action: :destroy
    define :create_correction, action: :create_correction
    define :cancel, args: [:invoice_id], action: :cancel
    define :toggle_skip, action: :toggle_skip
    define :generate_share_token, action: :generate_share_token
    define :lock_for_ksef, action: :lock_for_ksef
    define :unlock_for_ksef, action: :unlock_for_ksef
    define :update_ksef_fields, action: :update_ksef_fields
    define :denormalize_item_names, action: :denormalize_item_names

    # Wizard
    define :confirm_from_draft,
      args: [
        :draft_id,
        {:optional, :invoice_number},
        :organization,
        {:optional, :should_send_emails}
      ]

    # Invoice numbering
    define :get_next_number, args: [:date, {:optional, :series}, {:optional, :omit_invoice_id}]
    define :validate_number, args: [:invoice_number, :issue_date, {:optional, :omit_invoice_id}]
    define :list_series, args: []

    define :dispatch_overdue_sales_invoice_reminders,
      action: :dispatch_overdue_sales_invoice_reminders
  end

  actions do
    defaults []

    read :read do
      description "List sales invoices with search, status, and reconciliation filters."
      primary? true

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
      argument :buyer_type, :atom, constraints: [one_of: [:company, :individual]]
      argument :is_cash, :boolean
      argument :is_reverse_charge, :boolean

      argument :limit, :integer do
        constraints min: 1
      end

      # Date filtering — conditional on date_field
      prepare {Firmowid.Ash.Invoicing.Preparations.FilterByDateField, []}

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
               columns:
                 ~w(buyer_full_name buyer_given_name buyer_surname invoice_number buyer_email buyer_description buyer_id item_names)}

      # Kind filter
      prepare build(filter: expr(ksef_invoice_kind == ^arg(:kind))) do
        where present(:kind)
      end

      prepare build(filter: expr(currency == ^arg(:currency))) do
        where present(:currency)
      end

      prepare build(filter: expr(gross_value >= ^arg(:amount_gt))) do
        where present(:amount_gt)
      end

      prepare build(filter: expr(gross_value <= ^arg(:amount_lt))) do
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

    create :create do
      description "Create a sales invoice with its line items."
      primary? true

      accept [
        :invoice_type,
        :invoice_number,
        :sale_date,
        :issue_date,
        :due_date,
        :payment_method,
        :currency,
        :is_cash_account,
        :is_reverse_charge,
        :skip_invoicing,
        :ksef_invoice_kind,
        :correction_reason,
        :counterparty_id,
        :corrected_invoice_id,
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
        :should_send_emails,
        :invoice_note,
        :internal_note
      ]

      argument :sales_invoice_items, {:array, :map}, allow_nil?: false

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)

      change {Changes.SetItemNames, []}
      change {Changes.SetIsCashAccount, []}
      change {Changes.ValidateCountryCode, field: :buyer_country}

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate present([:issue_date, :currency]), message: "Pole jest wymagane"

      validate {Validations.ValidateItemsNotEmpty, field: :sales_invoice_items, source: :argument}

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    update :update do
      description "Update an existing sales invoice and its editable fields."
      primary? true
      require_atomic? false

      accept [
        :invoice_type,
        :invoice_number,
        :sale_date,
        :issue_date,
        :due_date,
        :payment_method,
        :currency,
        :is_cash_account,
        :is_reverse_charge,
        :ksef_invoice_kind,
        :correction_reason,
        :counterparty_id,
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
        :should_send_emails,
        :invoice_note,
        :internal_note
      ]

      argument :sales_invoice_items, {:array, :map}

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)

      change {Changes.SetItemNames, []}
      change {Changes.SetIsCashAccount, []}
      change {Changes.ValidateCountryCode, field: :buyer_country}

      validate {Validations.CheckIfLocked, []}

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate {Validations.ValidateItemsNotEmpty, field: :sales_invoice_items, source: :argument} do
        where present(:sales_invoice_items)
      end

      validate string_length(:internal_note, max: 10_000) do
        where present(:internal_note)
      end
    end

    update :attach_suggested_counterparty do
      description "Attach an unassigned invoice to a currently suggested counterparty."
      require_atomic? false
      accept []

      argument :counterparty_id, :uuid_v7, allow_nil?: false

      validate {Validations.CheckIfLocked, []}

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

    create :create_correction do
      description "Create a correction invoice for an existing sales invoice."

      accept [
        :invoice_number,
        :issue_date,
        :sale_date,
        :due_date,
        :correction_reason,
        :payment_method,
        :currency,
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
        :buyer_email,
        :buyer_phone,
        :buyer_description,
        :should_send_emails,
        :is_reverse_charge
      ]

      argument :original_invoice_id, :uuid_v7, allow_nil?: false
      argument :sales_invoice_items, {:array, :map}, allow_nil?: false

      change {Changes.PrepareCorrection, []}

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)

      change {Changes.SetItemNames, []}
      change {Changes.ValidateCountryCode, field: :buyer_country}

      validate present([:invoice_number, :issue_date]), message: "Pole jest wymagane"

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate string_length(:correction_reason, max: 256),
        message: "Powód korekty może mieć maksymalnie 256 znaków"

      validate {Validations.ValidateItemsNotEmpty, field: :sales_invoice_items, source: :argument}
    end

    destroy :destroy do
      description "Delete a sales invoice when deletion is allowed."
      require_atomic? false

      validate {Validations.CheckIfLocked, []}

      validate fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :ksef_number) do
          {:error, field: :base, message: "KSeF-submitted invoices cannot be deleted"}
        else
          :ok
        end
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
    end

    update :lock_for_ksef do
      description "Lock a sales invoice for KSeF submission processing."
      require_atomic? false
      accept []
      change set_attribute(:locked_at, &DateTime.utc_now/0)
    end

    update :unlock_for_ksef do
      description "Unlock a sales invoice after KSeF processing finishes or fails."
      require_atomic? false
      accept []
      change set_attribute(:locked_at, nil)
    end

    update :update_ksef_fields do
      description "Update KSeF tracking fields stored on this sales invoice."
      require_atomic? false
      accept [:ksef_number, :ksef_session_reference_number, :ksef_invoice_checksum, :locked_at]
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
          |> Ash.load!(
            [
              :effective_snapshot,
              :sales_invoice_items,
              latest_correction: correction_snapshot_load,
              corrections: :sales_invoice_items
            ],
            opts
          )

        if invoice.ksef_invoice_kind == :vat and invoice.ksef_number != nil do
          latest =
            case invoice.latest_correction do
              %{__struct__: __MODULE__} = correction ->
                Ash.load!(correction, correction_snapshot_load, opts)

              _ ->
                Ash.load!(invoice, correction_snapshot_load, opts)
            end

          issue_date = Date.utc_today()

          # Get next FK-series number
          {:ok, invoice_number} =
            issue_date
            |> __MODULE__.input_to_get_next_number("FK", nil, opts)
            |> Ash.run_action(opts)

          zeroed_items =
            Enum.map(latest.sales_invoice_items, fn item ->
              item
              |> Map.take([:index, :name, :unit, :unit_price, :vat_rate])
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
            Keyword.put(opts, :action, :create_correction)
          )
        else
          {:error, "can only cancel KSeF-submitted VAT invoices"}
        end
      end
    end

    action :confirm_from_draft, :struct do
      description "Create a sales invoice from a completed wizard draft."
      primary? true
      constraints instance_of: __MODULE__

      argument :draft_id, :uuid_v7, allow_nil?: false
      argument :invoice_number, :string
      argument :organization, :map, allow_nil?: false
      argument :should_send_emails, :boolean, default: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        draft =
          Firmowid.Ash.Invoicing.WizardDraft
          |> Ash.get!(input.arguments.draft_id, opts)
          |> Ash.load!([:items], opts)

        org = input.arguments.organization

        items =
          draft.items
          |> Enum.with_index()
          |> Enum.map(fn {item, idx} ->
            item
            |> Map.take([:name, :quantity, :unit, :unit_price, :vat_rate])
            |> Map.put(:index, idx)
          end)

        attrs = %{
          counterparty_id: draft.counterparty_id,
          buyer_type: draft.buyer_type,
          buyer_id: draft.buyer_id,
          buyer_full_name: draft.buyer_full_name,
          buyer_given_name: draft.buyer_given_name,
          buyer_surname: draft.buyer_surname,
          buyer_pesel: draft.buyer_pesel,
          buyer_display_name: draft.buyer_display_name,
          buyer_address: draft.buyer_address,
          buyer_country: draft.buyer_country,
          buyer_email: draft.buyer_email,
          buyer_phone: draft.buyer_phone,
          buyer_description: draft.buyer_description,
          invoice_type: draft.invoice_type,
          is_reverse_charge: draft.is_reverse_charge,
          currency: draft.currency,
          seller_account_number: draft.seller_account_number,
          sale_date: draft.sale_date,
          due_date: draft.due_date,
          payment_method: draft.payment_method,
          invoice_number: input.arguments.invoice_number,
          issue_date: Date.utc_today(),
          seller_display_name: org[:name] || org["name"],
          seller_address: org[:address] || org["address"],
          seller_nip: org[:nip] || org["nip"],
          is_cash_account: draft.payment_method == :cash,
          invoice_note: draft.invoice_note,
          internal_note: draft.internal_note,
          should_send_emails: input.arguments.should_send_emails,
          sales_invoice_items: items
        }

        case Ash.create(__MODULE__, attrs, Keyword.put(opts, :action, :create)) do
          {:ok, invoice} ->
            Ash.destroy!(draft, opts)
            {:ok, invoice}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    action :get_next_number, :string do
      description "Return the next available invoice number for a date and optional series."
      argument :date, :date, allow_nil?: false
      argument :series, :string
      argument :omit_invoice_id, :uuid

      run fn input, context ->
        date = input.arguments.date
        year = date.year
        month = date.month
        series = input.arguments[:series]
        omit_invoice_id = input.arguments[:omit_invoice_id]
        opts = Ash.Context.to_opts(context)

        existing_numbers =
          month
          |> read_invoice_numbers_matching(year, series, omit_invoice_id, opts)
          |> Enum.map(&parse_invoice_number/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, %{num: num}} -> num end)

        starting_num =
          case Enum.max(existing_numbers, fn -> 0 end) do
            0 -> 1
            max_num -> max_num + 1
          end

        {:ok, find_free_invoice_number(starting_num, month, year, series, omit_invoice_id, opts)}
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
          |> Map.values()
          |> Enum.sort_by(fn num -> if String.contains?(num, "/A"), do: 1, else: 0 end)

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
            {:ok, %{num: current_num, series: parsed_series}} ->
              {:ok, expected} =
                %{date: issue_date, series: parsed_series, omit_invoice_id: omit_invoice_id}
                |> __MODULE__.input_to_get_next_number(opts)
                |> Ash.run_action(opts)

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
  end

  policies do
    policy_group always() do
      policy {SystemActorRole, roles: [:sales_invoice_processor]} do
        authorize_if always()
      end

      policy AshObanInteraction do
        authorize_if action(:dispatch_overdue_sales_invoice_reminders)
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
        authorize_if action([:lock_for_ksef, :unlock_for_ksef, :update_ksef_fields])
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

      # Only system actors/AshOban may run scheduled reminder scans - users have no UI for this.
      policy action(:dispatch_overdue_sales_invoice_reminders) do
        forbid_if always()
      end
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "sales_invoice"

    publish :create, ["created", :_tenant]
    publish :update, ["updated", :_tenant]
    publish :destroy, ["destroyed", :_tenant]
    publish :toggle_skip, ["updated", :_tenant]
    publish :create_correction, ["created", :_tenant]
    publish :generate_share_token, ["updated", :_tenant]
    publish :attach_suggested_counterparty, ["updated", :_tenant]
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

    attribute :skip_invoicing, :boolean, default: false, public?: true
    attribute :should_send_emails, :boolean, default: false, public?: true

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
    # Public note visible on invoice/PDF and sent to KSeF (StopkaFaktury)
    attribute :invoice_note, :string, public?: true
    # Internal-only note, visible inside Firmowid only. Max 10_000 chars.
    attribute :internal_note, :string, public?: false
    # Validate internal_note length (DB will allow large text but enforce here)
    # Use an action-level validation instead of a bare validate/1 call inside attributes

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
      source_attribute :id
      destination_attribute :resource_id
    end
  end

  calculations do
    EffectiveFields.effective_correction_calculations()

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
    # WizardDraft, and Counterparty (as :tax_id_type) because Ash expr()
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
      nils_distinct?: false,
      message: "numer faktury już istnieje dla tej organizacji"
  end

  # Invoice numbering helpers -------------------------------------------------

  @invoice_number_regex ~r/^(\d+)\/(\d+)\/(\d+)(?:\/(.+))?$/

  @doc """
  Parses an invoice number in the `NN/MM/YYYY[/SERIES]` format.

  Returns parsed numeric parts and optional series as a map, or `:error` for
  invalid input.
  """
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
  Formats invoice number parts as `NN/MM/YYYY` or `NN/MM/YYYY/SERIES`.
  """
  def format_invoice_number(num, month, year, nil) do
    "#{String.pad_leading("#{num}", 2, "0")}/#{String.pad_leading("#{month}", 2, "0")}/#{year}"
  end

  def format_invoice_number(num, month, year, series) do
    "#{String.pad_leading("#{num}", 2, "0")}/#{String.pad_leading("#{month}", 2, "0")}/#{year}/#{series}"
  end

  defp build_series_pattern(month, year, nil) do
    month_str = String.pad_leading("#{month}", 2, "0")
    "^\\d+/#{month_str}/#{year}$"
  end

  defp build_series_pattern(month, year, series) do
    month_str = String.pad_leading("#{month}", 2, "0")
    escaped_series = Regex.escape(series)
    "^\\d+/#{month_str}/#{year}/#{escaped_series}$"
  end

  defp find_free_invoice_number(num, month, year, series, omit_invoice_id, opts) do
    invoice_number = format_invoice_number(num, month, year, series)

    if invoice_number_exists?(invoice_number, omit_invoice_id, opts) do
      find_free_invoice_number(num + 1, month, year, series, omit_invoice_id, opts)
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

  # Reads all invoice numbers matching a series pattern (month/year/series).
  # Uses fragment("? ~ ?", ...) for Postgres regex — Ash has no native regex operator.
  # Same escape hatch pattern as ParadeDB `&&&`.
  defp read_invoice_numbers_matching(month, year, series, omit_invoice_id, opts) do
    series_pattern = build_series_pattern(month, year, series)

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
    |> Ash.read!(opts)
    |> Enum.map(& &1.invoice_number)
  end

  @doc """
  Returns all non-nil invoice numbers visible in the provided Ash context.
  """
  def read_all_invoice_numbers(opts) do
    __MODULE__
    |> Ash.Query.filter(not is_nil(invoice_number))
    |> Ash.read!(opts)
    |> Enum.map(& &1.invoice_number)
  end
end
