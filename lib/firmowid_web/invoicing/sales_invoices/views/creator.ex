defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Creator do
  @moduledoc """
  LiveView for the sales invoice creator wizard.

  Uses `WizardDraft` (Ash ETS resource) for ephemeral wizard state,
  # TODO: move organization validation (validate_organization_for_invoicing)
  # to Ash-level command validation.
  `AshPhoenix.Form` for per-step form building and validation, and
  `SalesInvoice.confirm_from_draft` for final invoice creation.

  The draft itself carries expression calculations (`buyer_id_type`,
  `buyer_display_name_label`) and aggregates (`net_value`, `vat_value`,
  `gross_value`) via its `has_many :items` relationship, so no intermediate
  `SalesInvoice` struct is needed — the loaded draft IS the `@invoice` assign.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.WizardDraft
  alias Firmowid.Ash.Ksef
  alias FirmowidWeb.Infrastructure.Utilities.PolishValues
  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.CreatorQueryParams
  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestions
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.QueryCodec
  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation

  require Logger

  embed_templates "creator_*"

  # Creator steps, the definitions - 1-indexed for display and URL
  @steps %{
    1 => :counterparty,
    2 => :items,
    3 => :payment,
    4 => :preview
  }
  @step_numbers Map.new(@steps, fn {k, v} -> {v, k} end)

  # Convert step name to URL number (1-indexed)
  defp step_to_number(step), do: Map.fetch!(@step_numbers, step)

  # Convert URL number to step name
  defp number_to_step(num) when is_map_key(@steps, num), do: Map.fetch!(@steps, num)
  defp number_to_step(_), do: :counterparty

  # Calculations and aggregates to load on the draft for template rendering
  @draft_loads [
    :buyer_id_type,
    :buyer_display_name_label,
    :net_value,
    :vat_value,
    :gross_value,
    items: [:net_value, :vat_value, :gross_value]
  ]

  @impl true
  def render(%{loading: true} = assigns), do: ~H""
  def render(%{step: :counterparty} = assigns), do: creator_counterparty(assigns)
  def render(%{step: :items} = assigns), do: creator_items(assigns)
  def render(%{step: :payment} = assigns), do: creator_payment(assigns)
  def render(%{step: :preview} = assigns), do: creator_preview(assigns)

  @impl true
  def mount(_params, _session, socket) do
    # Load static data that doesn't change during the wizard
    socket =
      socket
      |> assign(:bank_accounts, Finances.list_bank_accounts!(scope: socket.assigns.ash_scope))
      |> assign(
        :last_counterparties,
        Invoicing.list_counterparties!(%{status: :active, limit: 25},
          load: [:display_label],
          scope: socket.assigns.ash_scope
        )
      )
      |> assign(:last_invoices, recent_invoices(socket.assigns.ash_scope))
      |> assign(:ksef_connected?, Ksef.get_credential(socket.assigns.ash_scope) != nil)
      |> assign(:open_counterparty_modal, false)
      |> assign(:can_manage_counterparties, socket.assigns.current_user.role == :admin)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.ash_scope

    case params do
      %{"szkic_kreatora" => creator_draft_id} ->
        handle_existing_draft(socket, scope, creator_draft_id, params)

      %{"skopiuj" => invoice_id} ->
        # Defer to connected socket — same reason as below
        if connected?(socket) do
          create_draft_from_copy(socket, scope, invoice_id)
        else
          {:noreply, assign(socket, :loading, true)}
        end

      _no_draft ->
        # Defer draft creation until the WebSocket connects — during static
        # render (disconnected), push_patch becomes an HTTP redirect which
        # would create a draft in the dead-render process and then immediately
        # redirect away from it.
        if connected?(socket) do
          create_and_redirect(socket, scope)
        else
          {:noreply, assign(socket, :loading, true)}
        end
    end
  end

  defp create_and_redirect(socket, scope) do
    org_id = scope.tenant

    case WizardDraft.create(%{organization_id: org_id}, scope: scope) do
      {:ok, draft} ->
        {:noreply, push_patch(socket, to: creator_draft_url(draft.id, :counterparty), replace: true)}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Nie masz uprawnień do wystawiania faktur sprzedażowych")
         |> push_navigate(to: ~p"/fakturowanie")}
    end
  end

  defp create_draft_from_copy(socket, scope, invoice_id) do
    org_id = scope.tenant

    item_calcs = [:net_value, :vat_value, :gross_value]

    case SalesInvoice.by_id(invoice_id, load: [sales_invoice_items: item_calcs], scope: scope) do
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Faktura nie została znaleziona")
         |> push_patch(to: Navigation.sales_invoice_creator_path(), replace: true)}

      {:ok, base_invoice} ->
        create_and_populate_draft_from_copy(socket, scope, org_id, base_invoice)
    end
  end

  defp create_and_populate_draft_from_copy(socket, scope, org_id, base_invoice) do
    case WizardDraft.create(%{organization_id: org_id}, scope: scope) do
      {:ok, draft} ->
        handle_populate_draft_result(
          socket,
          org_id,
          populate_draft_from_invoice(draft, base_invoice, socket.assigns.bank_accounts, scope)
        )

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Nie masz uprawnień do wystawiania faktur sprzedażowych")
         |> push_navigate(to: ~p"/fakturowanie")}
    end
  end

  defp handle_populate_draft_result(socket, org_id, {:ok, draft}) do
    invoice = load_draft_with_calcs(draft, socket.assigns.ash_scope)
    socket = assign(socket, invoice: invoice, creator_draft_id: draft.id, org_id: org_id)
    {:noreply, push_patch(socket, to: creator_draft_url(draft.id, :items), replace: true)}
  end

  defp handle_populate_draft_result(socket, org_id, {:partial, draft, changeset}) do
    invoice = load_draft_with_calcs(draft, socket.assigns.ash_scope)
    socket = assign(socket, invoice: invoice, creator_draft_id: draft.id, org_id: org_id)
    {:noreply, setup_partial_copy(socket, changeset, draft.id)}
  end

  defp populate_draft_from_invoice(draft, base_invoice, bank_accounts, scope) do
    default_bank_account =
      Enum.find(bank_accounts, &(&1.is_default and &1.currency == base_invoice.currency))

    items =
      Enum.map(base_invoice.sales_invoice_items, fn item ->
        %{
          index: item.index,
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          unit_price: item.unit_price,
          vat_rate: item.vat_rate
        }
      end)

    attrs = %{
      counterparty_id: base_invoice.counterparty_id,
      buyer_type: base_invoice.buyer_type,
      buyer_id: base_invoice.buyer_id,
      buyer_full_name: base_invoice.buyer_full_name,
      buyer_given_name: base_invoice.buyer_given_name,
      buyer_surname: base_invoice.buyer_surname,
      buyer_pesel: base_invoice.buyer_pesel,
      buyer_display_name: base_invoice.buyer_display_name,
      buyer_address: base_invoice.buyer_address,
      buyer_country: base_invoice.buyer_country,
      buyer_email: base_invoice.buyer_email,
      buyer_phone: base_invoice.buyer_phone,
      buyer_description: base_invoice.buyer_description,
      invoice_type: base_invoice.invoice_type,
      is_reverse_charge: base_invoice.is_reverse_charge,
      currency: base_invoice.currency,
      payment_method: base_invoice.payment_method,
      seller_account_number: if(default_bank_account, do: default_bank_account.iban),
      invoice_note: base_invoice.invoice_note,
      internal_note: base_invoice.internal_note,
      items: items
    }

    case WizardDraft.populate_from_invoice(draft, attrs, scope: scope) do
      {:ok, draft} ->
        # Validate counterparty data — old invoices may have data that no longer passes validation
        form =
          draft
          |> AshPhoenix.Form.for_update(:update_counterparty, scope: scope)
          |> AshPhoenix.Form.validate(
            draft
            |> Map.from_struct()
            |> Map.new(fn {k, v} -> {to_string(k), v} end)
          )

        if form.valid? do
          {:ok, draft}
        else
          {:partial, draft, form}
        end

      {:error, _} = error ->
        error
    end
  end

  defp setup_partial_copy(socket, form, creator_draft_id) do
    socket
    |> assign(:counterparty_form, to_form(form))
    |> assign(:open_counterparty_modal, true)
    |> LiveToast.put_toast(
      :error,
      "Skopiowano pozycje z faktury, ale dane kontrahenta wymagają poprawy — uzupełnij formularz."
    )
    |> push_patch(to: creator_draft_url(creator_draft_id, :counterparty), replace: true)
  end

  defp handle_existing_draft(socket, scope, creator_draft_id, params) do
    # If we already have this draft loaded and step hasn't changed,
    # just update step-specific params (tab, search) without refetching
    current_creator_draft_id = socket.assigns[:creator_draft_id]
    current_step = socket.assigns[:step]
    requested_step = parse_step_param(params["krok"])

    if current_creator_draft_id == creator_draft_id and current_step == requested_step do
      {:noreply, maybe_setup_step(socket, requested_step, params)}
    else
      fetch_and_restore_draft(socket, scope, creator_draft_id, params)
    end
  end

  defp fetch_and_restore_draft(socket, scope, creator_draft_id, params) do
    case Invoicing.get_wizard_draft(creator_draft_id, scope: scope) do
      {:ok, draft} ->
        restore_draft(socket, scope, draft, params)

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Szkic kreatora nie został znaleziony, rozpoczynamy od nowa")
         |> push_patch(to: Navigation.sales_invoice_creator_path(), replace: true)}
    end
  end

  defp restore_draft(socket, scope, draft, params) do
    org_id = scope.tenant
    requested_step = parse_step_param(params["krok"])

    # Load items for calculate_max_step and for @invoice assign
    draft = Ash.load!(draft, [:items], scope: scope)
    max_allowed_step = calculate_max_step(draft)

    # Clamp requested step to what's allowed based on data
    step = clamp_step(requested_step, max_allowed_step)

    invoice = load_draft_with_calcs(draft, scope)

    socket =
      socket
      |> assign(:invoice, invoice)
      |> assign(:draft, draft)
      |> assign(:creator_draft_id, draft.id)
      |> assign(:org_id, org_id)
      |> assign(:step, step)
      |> assign(:step_number, step_to_number(step))
      |> maybe_setup_step(step, params)

    # If step was clamped, redirect to correct URL
    socket =
      if step == requested_step do
        socket
      else
        push_patch(socket, to: creator_draft_url(draft.id, step), replace: true)
      end

    {:noreply, socket}
  end

  # Load expression calculations and aggregates on a WizardDraft so it can
  # serve as the @invoice assign in templates. The loaded draft has:
  #   - :buyer_id_type, :buyer_display_name_label (expression calcs)
  #   - :net_value, :vat_value, :gross_value (sum aggregates over items)
  #   - items with :net_value, :vat_value, :gross_value loaded
  defp load_draft_with_calcs(draft, scope) do
    Ash.load!(draft, @draft_loads, scope: scope)
  end

  # Parse step from URL param (number string) to step name atom
  defp parse_step_param(nil), do: :counterparty

  defp parse_step_param(step) when is_binary(step) do
    case Integer.parse(step) do
      {parsed_step, ""} -> number_to_step(parsed_step)
      _error -> :counterparty
    end
  end

  defp parse_step_param(step) when is_integer(step), do: number_to_step(step)
  defp parse_step_param(step) when is_atom(step), do: step

  # Clamp step to max allowed based on draft data
  defp clamp_step(requested_step, max_allowed_step) do
    requested_idx = step_to_number(requested_step)
    max_idx = step_to_number(max_allowed_step)

    if requested_idx <= max_idx do
      requested_step
    else
      max_allowed_step
    end
  end

  defp calculate_max_step(draft) do
    cond do
      draft.sale_date && draft.due_date && draft.payment_method -> :preview
      has_items?(draft) -> :payment
      draft.buyer_country -> :items
      true -> :counterparty
    end
  end

  defp has_items?(%{items: items}) when is_list(items), do: items != []
  defp has_items?(_draft), do: false

  defp maybe_setup_step(socket, :counterparty, params) do
    # Counterparty selection - setup search/tabs
    last_counterparties = socket.assigns.last_counterparties
    query_params = CreatorQueryParams.parse_query_params(params, last_counterparties)
    no_search? = is_nil(query_params.search)

    # Always populate the stream when entering counterparty step.
    # Even if search hasn't changed, the stream container may have been destroyed
    # when switching to a different step's template, so we need to re-send the data.
    socket
    |> assign(:query_params, query_params)
    |> assign(:tab, query_params.tab)
    |> update_counterparty_stream(
      query_params.search,
      no_search?,
      query_params.filter,
      query_params.sort_order
    )
    |> maybe_init_counterparty_form()
  end

  defp maybe_setup_step(socket, :items, _params) do
    draft = socket.assigns.draft
    scope = socket.assigns.ash_scope

    # Ensure items are loaded before building the form — auto?: true
    # detects manage_relationship(:items, ...) and builds nested forms.
    # If items aren't loaded, on_missing: :destroy would wipe all items.
    draft = Ash.load!(draft, [:items], scope: scope)

    ash_form =
      AshPhoenix.Form.for_update(draft, :update_items, scope: scope, forms: [auto?: true])

    # Ensure at least one empty item row exists
    ash_form =
      if Enum.empty?(Map.get(ash_form.forms, :items, [])) do
        AshPhoenix.Form.add_form(ash_form, [:items])
      else
        ash_form
      end

    initial_params = %{
      "currency" => draft.currency,
      "is_reverse_charge" => draft.is_reverse_charge,
      "items" => initial_item_params(draft.items || [])
    }

    ash_form = AshPhoenix.Form.validate(ash_form, initial_params)

    socket
    |> assign(:draft, draft)
    |> assign(:items_form, to_form(ash_form))
    |> assign(:items_field, :items)
  end

  defp maybe_setup_step(socket, :payment, _params) do
    draft = socket.assigns.draft
    scope = socket.assigns.ash_scope
    bank_accounts = socket.assigns.bank_accounts

    # Find selected bank account: match by IBAN if set, otherwise find default for currency
    selected_bank_account =
      find_selected_bank_account(bank_accounts, draft.seller_account_number, draft.currency)

    defaults =
      %{
        "payment_method" => draft.payment_method || :transfer,
        "seller_account_number" => draft.seller_account_number || (selected_bank_account && selected_bank_account.iban)
      }
      |> maybe_put_date("sale_date", draft.sale_date)
      |> maybe_put_date("due_date", draft.due_date)

    form =
      draft
      |> AshPhoenix.Form.for_update(:update_payment, scope: scope)
      |> AshPhoenix.Form.validate(defaults)
      |> to_form()

    socket
    |> assign(:selected_bank_account, selected_bank_account)
    |> assign(:payment_form, form)
  end

  defp maybe_setup_step(socket, :preview, _params) do
    # Preview - load organization and build preview invoice map for Pdf component
    org_id = socket.assigns.org_id
    organization = Core.get_organization!(org_id, scope: socket.assigns.ash_scope)
    invoice = socket.assigns.invoice

    # Generate preview data
    issue_date = Date.utc_today()
    scope = socket.assigns.ash_scope
    invoice_number = SalesInvoice.get_next_number!(issue_date, nil, nil, scope: scope)

    # Get all series suggestions (nil = default, "A" = always shown, plus any existing)
    series_suggestions = Invoicing.get_next_numbers_for_series(issue_date, scope: scope)

    # Validate initial invoice number
    invoice_warnings =
      SalesInvoice.validate_number!(invoice_number, issue_date, nil, scope: scope)

    # Build preview invoice map with seller data from organization
    logo_url = Invoicing.get_logo_url(org_id, scope: socket.assigns.ash_scope)

    preview_invoice = build_preview_map(invoice, organization, invoice_number, issue_date)

    # Get currency rate for non-PLN invoices
    currency_rate = Invoicing.get_currency_rate(preview_invoice)

    socket
    |> assign(:organization, organization)
    |> assign(:invoice_number, invoice_number)
    |> assign(:logo_url, logo_url)
    |> assign(:preview_invoice, preview_invoice)
    |> assign(:currency_rate, currency_rate)
    |> assign(:series_suggestions, series_suggestions)
    |> assign(:invoice_warnings, invoice_warnings)
  end

  defp maybe_setup_step(socket, _step, _params) do
    socket
  end

  defp initial_item_params([]), do: [%{}]

  defp initial_item_params(items) do
    Enum.map(items, fn item ->
      %{
        "name" => item.name,
        "quantity" => item.quantity,
        "unit" => item.unit,
        "unit_price" => item.unit_price,
        "vat_rate" => item.vat_rate
      }
    end)
  end

  # Build a plain map from the loaded WizardDraft for the Pdf/Template component.
  # The Pdf component declares `attr :sales_invoice, :map` so a plain map works.
  # We map WizardDraft fields + items to the names the template expects.
  defp build_preview_map(draft, organization, invoice_number, issue_date) do
    items =
      (draft.items || [])
      |> Enum.sort_by(& &1.index)
      |> Enum.map(fn item ->
        %{
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          unit_price: item.unit_price,
          vat_rate: item.vat_rate,
          net_value: item.net_value,
          vat_value: item.vat_value,
          gross_value: item.gross_value
        }
      end)

    %{
      invoice_number: invoice_number,
      issue_date: issue_date,
      sale_date: draft.sale_date,
      due_date: draft.due_date,
      currency: draft.currency,
      invoice_type: draft.invoice_type,
      is_reverse_charge: draft.is_reverse_charge,
      is_cash_account: draft.payment_method == :cash,
      payment_method: draft.payment_method,
      seller_account_number: draft.seller_account_number,
      seller_display_name: organization.name,
      seller_address: organization.address,
      seller_nip: organization.nip,
      buyer_type: draft.buyer_type,
      buyer_id: draft.buyer_id,
      buyer_full_name: draft.buyer_full_name,
      buyer_given_name: draft.buyer_given_name,
      buyer_surname: draft.buyer_surname,
      buyer_pesel: draft.buyer_pesel,
      buyer_address: draft.buyer_address,
      buyer_country: draft.buyer_country,
      net_value: draft.net_value,
      vat_value: draft.vat_value,
      gross_value: draft.gross_value,
      sales_invoice_items: items,
      invoice_note: draft.invoice_note,
      internal_note: draft.internal_note,
      # Fields the template checks but aren't relevant for new invoices
      ksef_invoice_kind: :vat,
      ksef_number: nil,
      corrected_invoice: nil,
      correction_reason: nil
    }
  end

  # When copying an invoice with invalid counterparty data, the form is pre-filled
  # with the copied data and the modal is set to auto-open. Don't overwrite it.
  defp maybe_init_counterparty_form(%{assigns: %{open_counterparty_modal: true}} = socket) do
    socket
  end

  defp maybe_init_counterparty_form(socket) do
    draft = socket.assigns.draft
    scope = socket.assigns.ash_scope

    form =
      draft
      |> AshPhoenix.Form.for_update(:update_counterparty, scope: scope)
      |> to_form()

    assign(socket, :counterparty_form, form)
  end

  defp reset_counterparty_modal(socket) do
    socket
    |> assign(:open_counterparty_modal, false)
    |> maybe_init_counterparty_form()
  end

  defp maybe_put_date(params, _key, nil), do: params

  defp maybe_put_date(params, key, %Date{} = date), do: Map.put(params, key, Date.to_iso8601(date))

  defp update_counterparty_stream(socket, search, no_search?, filter, sort_order) do
    counterparties =
      case Invoicing.list_counterparties(
             %{search: search, type: filter, status: :active, sort_order: sort_order, limit: 25},
             scope: socket.assigns.ash_scope
           ) do
        {:ok, results} -> results
        _ -> []
      end

    socket
    |> assign(
      :params,
      to_form(
        %{
          "szukaj" => search,
          "typ" => filter_to_string(filter),
          "kolejnosc" => PolishValues.encode_sort_order(sort_order)
        },
        as: "search_form"
      )
    )
    |> stream(:counterparties, counterparties, reset: true)
    |> assign(:counterparties_empty?, Enum.empty?(counterparties))
    |> assign(:counterparties_zero_state?, Enum.empty?(counterparties) and no_search?)
  end

  defp filter_to_string(nil), do: ""
  defp filter_to_string(filter), do: QueryCodec.encode_counterparty_type(filter)

  # Navigation helpers

  defp creator_draft_url(creator_draft_id, step) when is_atom(step) do
    creator_draft_id
    |> CreatorQueryParams.draft_step_params(step_to_number(step))
    |> Navigation.sales_invoice_creator_path()
  end

  defp counterparty_management_new_path(assigns) do
    return_to =
      CreatorQueryParams.draft_step_params(
        assigns.creator_draft_id,
        step_to_number(:counterparty),
        assigns.query_params
      )

    ManagementNavigation.counterparty_new_path(%{
      powrot_do: Navigation.sales_invoice_creator_path(return_to)
    })
  end

  defp counterparty_tabs(assigns) do
    assigns.last_counterparties
    |> counterparty_tab_definitions(assigns.last_invoices)
    |> Enum.map(fn {tab, label} ->
      %{
        tab: tab,
        label: label,
        patch: counterparty_tab_patch(assigns, tab)
      }
    end)
  end

  defp counterparty_tab_definitions([], []), do: []
  defp counterparty_tab_definitions([], _last_invoices), do: [last_invoices: "Ostatnie faktury"]

  defp counterparty_tab_definitions(_last_counterparties, _last_invoices) do
    [last_counterparties: "Ostatnio wybierani", last_invoices: "Ostatnie faktury"]
  end

  defp counterparty_tab_patch(assigns, tab) do
    params =
      CreatorQueryParams.draft_step_params(
        assigns.creator_draft_id,
        assigns.step_number,
        Map.put(assigns.query_params, :tab, tab)
      )

    Navigation.sales_invoice_creator_path(params)
  end

  # Query params management (for step 0 tabs/search)

  defp parse_filter(raw_filter), do: QueryCodec.parse_counterparty_type(raw_filter)

  defp parse_sort_order(raw_sort_order), do: PolishValues.parse_sort_order(raw_sort_order) || :asc

  defp update_counterparty_query_params(socket, updates) do
    query_params = Map.merge(socket.assigns.query_params, Map.new(updates))

    params =
      CreatorQueryParams.draft_step_params(
        socket.assigns.creator_draft_id,
        step_to_number(:counterparty),
        query_params
      )

    push_patch(socket, to: Navigation.sales_invoice_creator_path(params))
  end

  @impl true
  def handle_event("add_item", %{"field" => field}, socket) do
    form =
      socket.assigns.items_form.source
      |> AshPhoenix.Form.add_form(String.to_existing_atom(field))
      |> to_form()

    {:noreply, assign(socket, :items_form, form)}
  end

  def handle_event("validate_items", %{"form" => params}, socket) do
    form =
      socket.assigns.items_form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :items_form, form)}
  end

  def handle_event("submit_items", %{"form" => params}, socket) do
    old_currency = socket.assigns.draft.currency

    case AshPhoenix.Form.submit(socket.assigns.items_form.source, params: params) do
      {:ok, updated_draft} ->
        # Reset bank account if currency changed
        updated_draft =
          if updated_draft.currency == old_currency do
            updated_draft
          else
            # Reset bank account when currency changes — avoids payment step
            # validations (sale_date/due_date not set yet)
            Invoicing.reset_wizard_draft_bank_account!(updated_draft,
              scope: socket.assigns.ash_scope
            )
          end

        invoice = load_draft_with_calcs(updated_draft, socket.assigns.ash_scope)

        socket =
          socket
          |> assign(:draft, updated_draft)
          |> assign(:invoice, invoice)

        {:noreply, push_patch(socket, to: creator_draft_url(socket.assigns.creator_draft_id, :payment))}

      {:error, form} ->
        {:noreply, assign(socket, items_form: to_form(form))}
    end
  end

  def handle_event("select_counterparty", %{"counterparty_id" => counterparty_id}, socket) do
    handle_counterparty_selection(socket, counterparty_id)
  end

  def handle_event("select_base_invoice", %{"invoice_id" => invoice_id}, socket) do
    scope = socket.assigns.ash_scope
    base_invoice = SalesInvoice.by_id!(invoice_id, load: [:sales_invoice_items], scope: scope)
    draft = socket.assigns.draft

    case populate_draft_from_invoice(draft, base_invoice, socket.assigns.bank_accounts, scope) do
      {:ok, updated_draft} ->
        invoice = load_draft_with_calcs(updated_draft, scope)

        socket =
          socket
          |> assign(:invoice, invoice)
          |> assign(:draft, updated_draft)

        {:noreply, push_patch(socket, to: creator_draft_url(draft.id, :items))}

      {:partial, updated_draft, changeset} ->
        invoice = load_draft_with_calcs(updated_draft, scope)

        socket =
          socket
          |> assign(:invoice, invoice)
          |> assign(:draft, updated_draft)

        {:noreply, setup_partial_copy(socket, changeset, draft.id)}
    end
  end

  def handle_event("search_counterparties", %{"search_form" => params}, socket) do
    updates = [
      search: params["szukaj"],
      filter: parse_filter(params["typ"]),
      sort_order: parse_sort_order(params["kolejnosc"])
    ]

    {:noreply, update_counterparty_query_params(socket, updates)}
  end

  def handle_event("clear_counterparty_filters", _params, socket) do
    {:noreply, update_counterparty_query_params(socket, search: nil, filter: nil)}
  end

  def handle_event("validate_counterparty", %{"form" => params}, socket) do
    form =
      socket.assigns.counterparty_form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :counterparty_form, form)}
  end

  def handle_event("close_counterparty_modal", _params, socket) do
    {:noreply, reset_counterparty_modal(socket)}
  end

  def handle_event("submit_counterparty", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.counterparty_form.source, params: params) do
      {:ok, updated_draft} ->
        invoice = load_draft_with_calcs(updated_draft, socket.assigns.ash_scope)

        socket =
          socket
          |> assign(:draft, updated_draft)
          |> assign(:invoice, invoice)
          |> assign(:open_counterparty_modal, false)

        {:noreply, push_patch(socket, to: creator_draft_url(socket.assigns.creator_draft_id, :items))}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:counterparty_form, to_form(form))
         |> LiveToast.put_toast(
           :error,
           "Nie udało się zapisać danych kontrahenta — sprawdź błędy formularza (np. NIP)."
         )}
    end
  end

  def handle_event("validate_payment", %{"form" => params}, socket) do
    form =
      socket.assigns.payment_form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :payment_form, form)}
  end

  def handle_event("suggest_payment_date", %{"field" => field, "suggestion" => suggestion}, socket) do
    with target when not is_nil(target) <- PaymentDateSuggestions.parse_target(field),
         suggestion_key when not is_nil(suggestion_key) <-
           PaymentDateSuggestions.parse_suggestion(suggestion) do
      today = Date.utc_today()
      current_params = socket.assigns.payment_form.source.params || %{}

      updated_params =
        PaymentDateSuggestions.apply_suggestion(
          current_params,
          target,
          suggestion_key,
          today,
          today
        )

      form =
        socket.assigns.payment_form.source
        |> AshPhoenix.Form.validate(updated_params)
        |> to_form()

      {:noreply, assign(socket, :payment_form, form)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select_bank_account", %{"account_id" => account_id}, socket) do
    bank_account = Enum.find(socket.assigns.bank_accounts, &(&1.id == account_id))

    case bank_account do
      nil ->
        {:noreply, socket}

      bank_account ->
        current_params = socket.assigns.payment_form.source.params || %{}

        {selected_bank_account, updated_params} =
          if socket.assigns.selected_bank_account &&
               socket.assigns.selected_bank_account.id == bank_account.id do
            {nil, Map.put(current_params, "seller_account_number", "")}
          else
            {bank_account, Map.put(current_params, "seller_account_number", bank_account.iban)}
          end

        form =
          socket.assigns.payment_form.source
          |> AshPhoenix.Form.validate(updated_params)
          |> to_form()

        socket =
          socket
          |> assign(:selected_bank_account, selected_bank_account)
          |> assign(:payment_form, form)

        {:noreply, socket}
    end
  end

  def handle_event("submit_payment", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.payment_form.source, params: params) do
      {:ok, updated_draft} ->
        invoice = load_draft_with_calcs(updated_draft, socket.assigns.ash_scope)

        socket =
          socket
          |> assign(:draft, updated_draft)
          |> assign(:invoice, invoice)

        {:noreply, push_patch(socket, to: creator_draft_url(socket.assigns.creator_draft_id, :preview))}

      {:error, form} ->
        {:noreply, assign(socket, payment_form: to_form(form))}
    end
  end

  def handle_event("update_invoice_number", %{"invoice_number" => invoice_number}, socket) do
    preview_invoice = Map.put(socket.assigns.preview_invoice, :invoice_number, invoice_number)
    issue_date = socket.assigns.preview_invoice.issue_date

    scope = socket.assigns.ash_scope

    invoice_warnings =
      SalesInvoice.validate_number!(invoice_number, issue_date, nil, scope: scope)

    {:noreply,
     socket
     |> assign(:invoice_number, invoice_number)
     |> assign(:preview_invoice, preview_invoice)
     |> assign(:invoice_warnings, invoice_warnings)}
  end

  def handle_event("update_notes", %{"invoice_note" => invoice_note, "internal_note" => internal_note}, socket) do
    scope = socket.assigns.ash_scope
    draft = socket.assigns.draft

    case WizardDraft.update_notes(
           draft,
           %{invoice_note: invoice_note, internal_note: internal_note},
           scope: scope
         ) do
      {:ok, updated_draft} ->
        invoice = load_draft_with_calcs(updated_draft, scope)

        preview_invoice =
          Map.merge(socket.assigns.preview_invoice, %{
            invoice_note: invoice_note,
            internal_note: internal_note
          })

        {:noreply,
         socket
         |> assign(:draft, updated_draft)
         |> assign(:invoice, invoice)
         |> assign(:preview_invoice, preview_invoice)}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  def handle_event("select_series", %{"number" => invoice_number}, socket) do
    # User clicked a series suggestion button - set the invoice number
    preview_invoice = Map.put(socket.assigns.preview_invoice, :invoice_number, invoice_number)
    issue_date = socket.assigns.preview_invoice.issue_date

    # Validate (should be empty for suggestions, but check anyway)
    scope = socket.assigns.ash_scope

    invoice_warnings =
      SalesInvoice.validate_number!(invoice_number, issue_date, nil, scope: scope)

    {:noreply,
     socket
     |> assign(:invoice_number, invoice_number)
     |> assign(:preview_invoice, preview_invoice)
     |> assign(:invoice_warnings, invoice_warnings)}
  end

  def handle_event("save_as_draft", _params, socket) do
    scope = socket.assigns.ash_scope
    organization = socket.assigns.organization
    draft = socket.assigns.draft

    case create_invoice_from_draft(draft, nil, organization, scope) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> put_flash(:info, "Faktura zapisana jako szkic")
         |> redirect(to: Navigation.sales_invoice_show_path(invoice))}

      {:error, error} ->
        Logger.error("Failed to save invoice as draft: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Nie udało się zapisać faktury")}
    end
  end

  def handle_event("confirm_invoice", _params, socket) do
    scope = socket.assigns.ash_scope
    organization = socket.assigns.organization
    draft = socket.assigns.draft
    invoice_number = socket.assigns.invoice_number

    with :ok <- validate_organization_for_invoicing(organization),
         {:ok, invoice} <- create_invoice_from_draft(draft, invoice_number, organization, scope) do
      {:noreply, push_navigate(socket, to: Navigation.sales_invoice_summary_path(invoice))}
    else
      {:error, error} ->
        Logger.error("Failed to confirm invoice: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, get_error_message(error))}
    end
  end

  def handle_event("send_to_ksef", _params, socket) do
    scope = socket.assigns.ash_scope
    organization = socket.assigns.organization
    draft = socket.assigns.draft
    invoice_number = socket.assigns.invoice_number

    with :ok <- validate_organization_for_invoicing(organization),
         {:ok, invoice} <- create_invoice_from_draft(draft, invoice_number, organization, scope) do
      submit_to_ksef_and_navigate(socket, invoice)
    else
      {:error, error} ->
        Logger.error("Failed to confirm invoice: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, get_error_message(error))}
    end
  end

  defp handle_counterparty_selection(socket, counterparty_id) do
    scope = socket.assigns.ash_scope

    case Counterparty.get(counterparty_id, scope: scope) do
      {:ok, counterparty} ->
        attrs = %{
          counterparty_id: counterparty.id,
          buyer_type: counterparty.type,
          buyer_id: counterparty.tax_id,
          buyer_full_name: counterparty.full_name,
          buyer_given_name: counterparty.given_name,
          buyer_surname: counterparty.surname,
          buyer_display_name: counterparty.display_name,
          buyer_address: counterparty.address,
          buyer_pesel: counterparty.pesel,
          buyer_country: counterparty.country,
          buyer_email: counterparty.email,
          buyer_phone: counterparty.phone,
          buyer_description: counterparty.description
        }

        case WizardDraft.update_counterparty(socket.assigns.draft, attrs, scope: scope) do
          {:ok, updated_draft} ->
            invoice = load_draft_with_calcs(updated_draft, scope)

            socket =
              socket
              |> assign(:draft, updated_draft)
              |> assign(:invoice, invoice)

            {:noreply, push_patch(socket, to: creator_draft_url(socket.assigns.creator_draft_id, :items))}

          {:error, _error} ->
            # Counterparty has invalid data (e.g. missing tax ID for required type).
            # Pre-fill the manual counterparty form with what we have and open the modal.
            form =
              socket.assigns.draft
              |> AshPhoenix.Form.for_update(:update_counterparty, scope: scope)
              |> AshPhoenix.Form.validate(Map.new(attrs, fn {k, v} -> {to_string(k), v} end))

            socket =
              socket
              |> assign(:counterparty_form, to_form(form))
              |> assign(:open_counterparty_modal, true)

            {:noreply,
             LiveToast.put_toast(
               socket,
               :error,
               "Dane kontrahenta wymagają uzupełnienia — popraw formularz."
             )}
        end

      {:error, error} ->
        Logger.warning("Failed to fetch counterparty during selection: #{inspect(error)}")

        {:noreply,
         LiveToast.put_toast(
           socket,
           :error,
           "Nie udało się pobrać danych kontrahenta. Spróbuj ponownie."
         )}
    end
  end

  defp submit_to_ksef_and_navigate(socket, invoice) do
    case Ksef.submit_sales_invoice(invoice.id, socket.assigns.ash_scope) do
      {:ok, _job} ->
        {:noreply, push_navigate(socket, to: Navigation.sales_invoice_summary_path(invoice))}

      {:error, reason} ->
        Logger.error("Failed to submit invoice to KSeF: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Faktura została wystawiona, ale wysyłka do KSeF nie powiodła się")
         |> push_navigate(to: Navigation.sales_invoice_summary_path(invoice))}
    end
  end

  defp create_invoice_from_draft(draft, invoice_number, organization, scope) do
    org_data = %{name: organization.name, address: organization.address, nip: organization.nip}
    SalesInvoice.confirm_from_draft(draft.id, invoice_number, org_data, scope: scope)
  end

  defp get_error_message(%Ash.Error.Invalid{} = error) do
    errors =
      error
      |> Ash.Error.to_ash_error()
      |> Map.get(:errors, [])

    messages =
      errors
      |> Enum.map(fn e -> Map.get(e, :message, "") end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case messages do
      [] -> "Nie udało się wystawić faktury"
      msgs -> Enum.join(msgs, ", ")
    end
  end

  defp get_error_message({:organization_validation, field}) do
    case field do
      :nip -> "Uzupełnij NIP firmy w ustawieniach organizacji."
      :name -> "Uzupełnij nazwę firmy w ustawieniach organizacji."
      :address -> "Uzupełnij adres firmy w ustawieniach organizacji."
    end
  end

  defp get_error_message(_), do: "Nie udało się wystawić faktury"

  @doc """
  Validates that organization has all required data for KSeF invoice submission.
  Returns `:ok` if valid, `{:error, {:organization_validation, field}}` otherwise.
  """
  def validate_organization_for_invoicing(organization) do
    cond do
      is_nil(organization.nip) or organization.nip == "" ->
        {:error, {:organization_validation, :nip}}

      is_nil(organization.name) or organization.name == "" ->
        {:error, {:organization_validation, :name}}

      is_nil(organization.address) or organization.address == "" ->
        {:error, {:organization_validation, :address}}

      true ->
        :ok
    end
  end

  def to_boolean(bool) when is_boolean(bool), do: bool
  def to_boolean("true"), do: true
  def to_boolean("false"), do: false

  # Extract suggestions from invoice number warnings for display in template
  def warning_suggestions({:invalid_format, suggestions}), do: suggestions
  def warning_suggestions({:duplicate, suggestions}), do: suggestions
  def warning_suggestions({:gap, expected}), do: [expected]

  # Find the selected bank account: first try matching IBAN, then default for currency
  defp find_selected_bank_account(bank_accounts, iban, currency) do
    Enum.find(bank_accounts, &(&1.iban == iban)) ||
      Enum.find(bank_accounts, &(&1.is_default and &1.currency == currency))
  end

  # Confirmed VAT invoices from the previous 2 months (replaces list_recent action).
  # The range covers [first_of_month - 2 months, last day of previous month].
  defp recent_invoices(scope) do
    today = Date.utc_today()
    first_of_this_month = %{today | day: 1}
    range_start = Date.shift(first_of_this_month, month: -2)
    range_end = Date.shift(first_of_this_month, day: -1)

    Invoicing.list_sales_invoices!(
      %{
        date_from: range_start,
        date_to: range_end,
        kind: :vat,
        submission: :confirmed,
        limit: 10
      },
      load: [:buyer_display_name_label, :gross_value],
      scope: scope
    )
  end

  attr :invoice, :any, default: nil
  attr :step, :any, required: true
  attr :title, :string, required: true

  def render_header(assigns) do
    buyer_name = assigns[:invoice] && assigns.invoice.buyer_display_name_label
    assigns = assign(assigns, :buyer_name, buyer_name)

    ~H"""
    <div class="flex flex-col gap-4">
      <div class="text-grey-500 flex flex-row gap-4 text-sm/snug">
        <h2>
          Kreator faktur |
          <span class="text-grey-700">
            <%= case @step do %>
              <% _step when is_integer(@step) -> %>
                Krok {@step}.
              <% _step when is_binary(@step) -> %>
                {@step}
            <% end %>
          </span>
        </h2>
        <%= if @buyer_name do %>
          <p class="ml-auto">
            Kontrahent <span class="text-grey-700">{@buyer_name}</span>
          </p>
          <p>
            <%= case @invoice.buyer_id_type do %>
              <% :nip -> %>
                NIP <span class="text-grey-700">{@invoice.buyer_id}</span>
              <% :eu_vat -> %>
                VAT-EU <span class="text-grey-700">{@invoice.buyer_id}</span>
              <% :other_id -> %>
                ID <span class="text-grey-700">{@invoice.buyer_id}</span>
              <% :optional_id -> %>
                <%= if @invoice.buyer_id && @invoice.buyer_id != "" do %>
                  ID <span class="text-grey-700">{@invoice.buyer_id}</span>
                <% end %>
              <% :no_id -> %>
                PESEL <span class="text-grey-700">{@invoice.buyer_pesel}</span>
            <% end %>
          </p>
        <% end %>
      </div>
      <h1 class="text-[27px]/tight font-medium">
        {@title}
      </h1>
    </div>
    """
  end
end
