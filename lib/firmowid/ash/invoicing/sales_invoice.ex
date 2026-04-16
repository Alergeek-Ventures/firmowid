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
    notifiers: [Ash.Notifier.PubSub],
    primary_read_warning?: false

  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Invoicing, as: InvoicingDomain
  alias Firmowid.Ash.Invoicing.Changes
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
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

  code_interface do
    # Reads
    define :by_id, args: [:id], action: :by_id
    define :get, args: [:id], action: :by_id
    define :read, action: :read
    define :by_share_token, args: [:token]

    # Writes
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
    define :create_correction, action: :create_correction
    define :cancel, args: [:invoice_id], action: :cancel
    define :toggle_skip, action: :toggle_skip
    define :generate_share_token, action: :generate_share_token
    define :lock_for_ksef, action: :lock_for_ksef
    define :unlock_for_ksef, action: :unlock_for_ksef
    define :update_ksef_fields, action: :update_ksef_fields

    # Wizard
    define :confirm_from_draft, args: [:draft_id, {:optional, :invoice_number}, :organization]

    # Invoice numbering
    define :get_next_number, args: [:date, {:optional, :series}, {:optional, :omit_invoice_id}]
    define :validate_number, args: [:invoice_number, :issue_date, {:optional, :omit_invoice_id}]
    define :list_series, args: []
  end

  actions do
    defaults []

    read :read do
      primary? true

      argument :date_from, :date
      argument :date_to, :date

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

      # Date filtering — conditional on date_field
      prepare {Firmowid.Ash.Invoicing.Preparations.FilterByDateField, []}

      # Kind filter
      prepare build(filter: expr(ksef_invoice_kind == ^arg(:kind))) do
        where present(:kind)
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

      prepare build(sort: [issue_date: :desc])
    end

    read :by_id do
      get_by [:id]
    end

    read :search do
      description "Full-text BM25 search for sales invoices with optional filters."

      argument :query, :string
      argument :currency, :string
      argument :amount_gt, :decimal
      argument :amount_lt, :decimal
      argument :date_from, :date
      argument :date_to, :date
      argument :only_unmatched, :boolean
      argument :buyer_type, :atom, constraints: [one_of: [:company, :individual]]
      argument :is_cash, :boolean
      argument :is_reverse_charge, :boolean

      # Only VAT invoices in search (not corrections)
      filter expr(ksef_invoice_kind == :vat)

      # ParadeDB BM25 search
      prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
               columns:
                 ~w(buyer_full_name buyer_given_name buyer_surname invoice_number buyer_email buyer_description buyer_id item_names)}

      # Conditional filters
      prepare build(filter: expr(currency == ^arg(:currency))) do
        where present(:currency)
      end

      prepare build(filter: expr(gross_value >= ^arg(:amount_gt))) do
        where present(:amount_gt)
      end

      prepare build(filter: expr(gross_value <= ^arg(:amount_lt))) do
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

      prepare build(filter: expr(buyer_type == ^arg(:buyer_type))) do
        where present(:buyer_type)
      end

      prepare build(filter: expr(is_cash_account == true)) do
        where argument_equals(:is_cash, true)
      end

      prepare build(filter: expr(is_reverse_charge == true)) do
        where argument_equals(:is_reverse_charge, true)
      end

      prepare build(sort: [issue_date: :desc])
      prepare build(limit: 50)
    end

    action :by_share_token, :struct do
      constraints instance_of: __MODULE__
      argument :token, :string, allow_nil?: false

      run fn input, context ->
        # Justified Ecto exception: cross-tenant lookup by share token.
        # Ash multitenancy requires tenant to be set before querying, but here
        # we don't know the tenant until we find the invoice. The initial lookup
        # uses Repo.one(skip_organization_id: true) to discover the org_id,
        # then the full read uses the standard :by_id action with proper tenant.
        import Ecto.Query

        token = input.arguments.token
        opts = Ash.Context.to_opts(context)

        {share_token, correction_id} =
          case String.split(token, ".", parts: 2) do
            [share_token] -> {share_token, nil}
            [share_token, correction_id] -> {share_token, correction_id}
          end

        invoice_row =
          if correction_id do
            case Ecto.UUID.dump(correction_id) do
              {:ok, _uuid} ->
                __MODULE__
                |> join(:inner, [correction], shared_invoice in __MODULE__,
                  on:
                    shared_invoice.share_token == ^share_token and
                      correction.corrected_invoice_id == shared_invoice.id
                )
                |> where(
                  [correction, _shared_invoice],
                  correction.id == ^correction_id and correction.ksef_invoice_kind == :kor
                )
                |> select(
                  [correction, _shared_invoice],
                  {correction.id, correction.organization_id}
                )
                |> Firmowid.Repo.one(skip_organization_id: true)

              :error ->
                nil
            end
          else
            __MODULE__
            |> where([i], i.share_token == ^share_token)
            |> select([i], {i.id, i.organization_id})
            |> Firmowid.Repo.one(skip_organization_id: true)
          end

        case invoice_row do
          nil ->
            {:ok, nil}

          {id, org_id} ->
            read_opts =
              opts
              |> Keyword.delete(:tenant)
              |> Keyword.put(:tenant, org_id)

            result =
              __MODULE__
              |> Ash.Query.for_read(:by_id, %{id: id}, read_opts)
              |> Ash.Query.load([:organization])
              |> Ash.read_one!(read_opts)

            {:ok, result}
        end
      end
    end

    # -- Write actions ---------------------------------------------------------

    create :create do
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

    create :create_correction do
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
        :is_reverse_charge
      ]

      argument :original_invoice_id, :uuid_v7, allow_nil?: false
      argument :sales_invoice_items, {:array, :map}, allow_nil?: false

      change {Changes.PrepareCorrection, []}

      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :sales_invoice_items}

      change manage_relationship(:sales_invoice_items, type: :direct_control)

      change {Changes.SetItemNames, []}

      validate present([:invoice_number, :issue_date]), message: "Pole jest wymagane"

      validate string_length(:correction_reason, max: 256),
        message: "Powód korekty może mieć maksymalnie 256 znaków"

      validate {Validations.ValidateItemsNotEmpty, field: :sales_invoice_items, source: :argument}
    end

    destroy :destroy do
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
      require_atomic? false
      accept []

      change fn changeset, _context ->
        current = Ash.Changeset.get_data(changeset, :skip_invoicing)
        Ash.Changeset.force_change_attribute(changeset, :skip_invoicing, !current)
      end
    end

    update :generate_share_token do
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
      require_atomic? false
      accept []
      change set_attribute(:locked_at, &DateTime.utc_now/0)
    end

    update :unlock_for_ksef do
      require_atomic? false
      accept []
      change set_attribute(:locked_at, nil)
    end

    update :update_ksef_fields do
      require_atomic? false
      accept [:ksef_number, :ksef_session_reference_number, :ksef_invoice_checksum, :locked_at]
    end

    # -- Generic actions -------------------------------------------------------

    # TODO: Extract the ~100-line inline `run fn` below into a named module
    # implementing `Ash.Resource.Actions.Implementation` (e.g. Actions.CancelInvoice).
    action :cancel, :struct do
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
            __MODULE__
            |> Ash.ActionInput.for_action(
              :get_next_number,
              %{date: issue_date, series: "FK"},
              opts
            )
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
      constraints instance_of: __MODULE__

      argument :draft_id, :uuid_v7, allow_nil?: false
      argument :invoice_number, :string
      argument :organization, :map, allow_nil?: false

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
                __MODULE__
                |> Ash.ActionInput.for_action(
                  :get_next_number,
                  %{date: issue_date, series: parsed_series, omit_invoice_id: omit_invoice_id},
                  opts
                )
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

    update :connect_transactions do
      description "Connect transactions to this sales invoice via the join table."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      change manage_relationship(:transaction_ids, :transactions, type: :append)
    end

    update :disconnect_transactions do
      description "Disconnect all transactions from this sales invoice."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, default: []

      change manage_relationship(:transaction_ids, :transactions, type: :append_and_remove)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # sales_invoice_processor: full access to all actions
    bypass {SystemActorRole, roles: [:sales_invoice_processor]} do
      authorize_if always()
    end

    # invoice_matcher: read + connect/disconnect transactions
    bypass {SystemActorRole, roles: [:invoice_matcher]} do
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:analysis_reader]} do
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:invoice_matcher]} do
      authorize_if action([:connect_transactions, :disconnect_transactions])
    end

    policy [
      action([:connect_transactions, :disconnect_transactions]),
      {AtLeastRole, role: :invoicing}
    ] do
      authorize_if always()
    end

    # ksef_session: lock/unlock/update ksef fields
    bypass {SystemActorRole, roles: [:ksef_session]} do
      authorize_if action([:lock_for_ksef, :unlock_for_ksef, :update_ksef_fields])
    end

    # anonymous: read actions only (share token access)
    bypass {SystemActorRole, roles: [:anonymous]} do
      authorize_if action([:by_id, :by_share_token])
    end

    # Other system actors: no access
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # :invoicing and :accountant: read-only
    policy [action_type(:read), {AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # :accountant: write + generic actions
    policy [
      action_type([:create, :update, :destroy]),
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
    prefix "sales_invoice"

    publish :create, ["created", :_tenant]
    publish :update, ["updated", :_tenant]
    publish :destroy, ["destroyed", :_tenant]
    publish :toggle_skip, ["updated", :_tenant]
    publish :create_correction, ["created", :_tenant]
    publish :generate_share_token, ["updated", :_tenant]
    publish :connect_transactions, ["updated", :_tenant]
    publish :disconnect_transactions, ["updated", :_tenant]
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

    has_one :latest_correction, __MODULE__ do
      destination_attribute :corrected_invoice_id
      sort locked_at: :desc_nils_last, inserted_at: :desc
    end

    has_many :sales_invoice_items, SalesInvoiceItem do
      sort index: :asc
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
              Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections do
      constraints items: [instance_of: __MODULE__]
    end

    # Boolean status calculations — DB-pushable, filterable, sortable
    calculate :is_draft, :boolean, expr(is_nil(invoice_number))
    calculate :is_confirmed, :boolean, expr(not is_nil(invoice_number))
    calculate :is_ksef_submitted, :boolean, expr(not is_nil(ksef_number))
    calculate :is_deletable, :boolean, expr(is_nil(ksef_number) and is_nil(locked_at))

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

  # Private helpers -----------------------------------------------------------

  # Invoice numbering helpers -------------------------------------------------

  @invoice_number_regex ~r/^(\d+)\/(\d+)\/(\d+)(?:\/(.+))?$/

  @doc false
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

  @doc false
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

  @doc false
  def read_all_invoice_numbers(opts) do
    __MODULE__
    |> Ash.Query.filter(not is_nil(invoice_number))
    |> Ash.read!(opts)
    |> Enum.map(& &1.invoice_number)
  end
end
