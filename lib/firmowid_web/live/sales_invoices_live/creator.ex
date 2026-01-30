defmodule FirmowidWeb.SalesInvoicesLive.Creator do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.Finances
  alias Firmowid.Ksef
  alias Firmowid.Ksef.VatRate
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.SalesInvoices.DraftStore
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  require Logger

  embed_templates "creator_*"

  # Step definitions - 1-indexed for display and URL
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

  @impl true
  def render(%{step: :counterparty} = assigns), do: creator_counterparty(assigns)
  def render(%{step: :items} = assigns), do: creator_items(assigns)
  def render(%{step: :payment} = assigns), do: creator_payment(assigns)
  def render(%{step: :preview} = assigns), do: creator_preview(assigns)

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(SalesInvoices, :read_sales_invoice, socket.assigns.current_user)
    Bodyguard.permit!(SalesInvoices, :create_sales_invoice, socket.assigns.current_user)

    # Load static data that doesn't change during the wizard
    socket =
      socket
      |> assign(:bank_accounts, Finances.list_bank_accounts())
      |> assign(:last_counterparties, SalesInvoices.list_counterparties())
      |> assign(:last_invoices, SalesInvoices.list_recent_invoices())
      |> assign(:ksef_connected?, Ksef.get_credential() != nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    org_id = Repo.get_org_id()

    case params do
      %{"draft" => draft_id} ->
        handle_existing_draft(socket, org_id, draft_id, params)

      %{"skopiuj" => invoice_id} ->
        create_draft_from_copy(socket, org_id, invoice_id)

      _no_draft ->
        create_and_redirect(socket, org_id)
    end
  end

  defp create_and_redirect(socket, org_id) do
    {:ok, draft_id, _draft} = DraftStore.create(org_id)
    {:noreply, push_patch(socket, to: draft_url(draft_id, :counterparty), replace: true)}
  end

  defp create_draft_from_copy(socket, org_id, invoice_id) do
    case SalesInvoices.get_sales_invoice(invoice_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Faktura nie została znaleziona")
         |> push_patch(to: ~p"/sprzedazowe", replace: true)}

      base_invoice ->
        Bodyguard.permit!(SalesInvoices, :show, socket.assigns.current_user, base_invoice)

        {:ok, draft_id, _draft} = DraftStore.create(org_id)
        invoice = build_copied_invoice(base_invoice, socket.assigns.bank_accounts)

        # Serialize invoice to draft format and persist
        socket = assign(socket, invoice: invoice, draft_id: draft_id, org_id: org_id)
        draft_data = serialize_to_draft(socket)

        DraftStore.put(org_id, draft_id, %{step: :items, data: draft_data})

        {:noreply, push_patch(socket, to: draft_url(draft_id, :items), replace: true)}
    end
  end

  defp handle_existing_draft(socket, org_id, draft_id, params) do
    # If we already have this draft loaded and step hasn't changed,
    # just update step-specific params (tab, search) without refetching
    current_draft_id = socket.assigns[:draft_id]
    current_step = socket.assigns[:step]
    requested_step = parse_step_param(params["step"])

    if current_draft_id == draft_id and current_step == requested_step do
      {:noreply, maybe_setup_step(socket, requested_step, params)}
    else
      fetch_and_restore_draft(socket, org_id, draft_id, params)
    end
  end

  defp fetch_and_restore_draft(socket, org_id, draft_id, params) do
    case DraftStore.get(org_id, draft_id) do
      {:ok, draft} ->
        restore_draft(socket, org_id, draft_id, draft, params)

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:info, "Szkic nie został znaleziony, rozpoczynamy od nowa")
         |> push_patch(to: ~p"/sprzedazowe", replace: true)}
    end
  end

  defp restore_draft(socket, org_id, draft_id, draft, params) do
    requested_step = parse_step_param(params["step"])
    max_allowed_step = calculate_max_step(draft.data)

    # Clamp requested step to what's allowed based on data
    step = clamp_step(requested_step, max_allowed_step)

    case restore_from_draft(socket, draft.data, step) do
      {:ok, socket} ->
        socket =
          socket
          |> assign(:draft_id, draft_id)
          |> assign(:org_id, org_id)
          |> assign(:step, step)
          |> assign(:step_number, step_to_number(step))
          |> maybe_setup_step(step, params)

        # If step was clamped, redirect to correct URL
        socket =
          if step == requested_step do
            socket
          else
            push_patch(socket, to: draft_url(draft_id, step), replace: true)
          end

        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to restore draft #{draft_id}: #{inspect(reason)}")
        DraftStore.delete(org_id, draft_id)

        {:noreply,
         socket
         |> put_flash(:info, "Poprzedni szkic byl nieprawidlowy, rozpoczynamy od nowa")
         |> push_patch(to: ~p"/sprzedazowe", replace: true)}
    end
  end

  # Parse step from URL param (number string) to step name atom
  defp parse_step_param(nil), do: :counterparty
  defp parse_step_param(step) when is_binary(step), do: number_to_step(String.to_integer(step))
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

  defp calculate_max_step(data) do
    cond do
      # Has all payment data -> can access preview and summary
      Map.has_key?(data, "sale_date") and Map.has_key?(data, "due_date") and
          Map.has_key?(data, "payment_method") ->
        :preview

      # Has items data -> can access payment
      Map.has_key?(data, "items") and data["items"] != [] ->
        :payment

      # Has counterparty data -> can access items
      Map.has_key?(data, "buyer_country") ->
        :items

      # Default -> counterparty
      true ->
        :counterparty
    end
  end

  defp maybe_setup_step(socket, :counterparty, params) do
    # Counterparty selection - setup search/tabs
    last_counterparties = socket.assigns.last_counterparties
    tab = parse_tab(params["tab"], last_counterparties)
    {search, no_search?} = parse_search(params["search"])
    filter = parse_filter(params["filter"])
    sort_order = parse_sort_order(params["sort_order"])
    query_params = %{tab: tab, search: search, filter: filter, sort_order: sort_order}

    # Always populate the stream when entering counterparty step.
    # Even if search hasn't changed, the stream container may have been destroyed
    # when switching to a different step's template, so we need to re-send the data.
    socket
    |> assign(:query_params, query_params)
    |> assign(:tab, tab)
    |> update_counterparty_stream(search, no_search?, filter, sort_order)
    |> assign(
      :counterparty_form,
      %SalesInvoice{} |> SalesInvoice.step1_changeset(%{buyer_type: :company}) |> to_form()
    )
  end

  defp maybe_setup_step(socket, :items, _params) do
    # Items - setup items form
    invoice = socket.assigns.invoice
    assign_items_form(socket, SalesInvoice.step2_changeset(invoice))
  end

  defp maybe_setup_step(socket, :payment, _params) do
    # Payment - setup payment form
    invoice = socket.assigns.invoice
    bank_accounts = socket.assigns.bank_accounts

    # Find selected bank account: match by IBAN if set, otherwise find default for currency
    selected_bank_account =
      find_selected_bank_account(bank_accounts, invoice.seller_account_number, invoice.currency)

    # Set default values for payment form
    defaults = %{
      "sale_date" => invoice.sale_date || Date.utc_today(),
      "due_date_days" => calculate_due_date_days(invoice) || 21,
      "payment_method" => :transfer,
      "seller_account_number" => selected_bank_account && selected_bank_account.iban
    }

    socket
    |> assign(:selected_bank_account, selected_bank_account)
    |> assign(:payment_form, invoice |> SalesInvoice.step3_changeset(defaults) |> to_form())
  end

  defp maybe_setup_step(socket, :preview, _params) do
    # Preview - load organization and build preview invoice
    org_id = socket.assigns.org_id
    {:ok, organization} = Accounts.get_organization(org_id)
    invoice = socket.assigns.invoice

    # Generate preview data
    issue_date = Date.utc_today()
    invoice_number = SalesInvoices.get_next_invoice_number(issue_date)

    # Get all series suggestions (nil = default, "A" = always shown, plus any existing)
    series_suggestions = SalesInvoices.get_next_numbers_for_series(issue_date)

    # Validate initial invoice number
    invoice_warnings = SalesInvoices.validate_invoice_number(invoice_number, issue_date)

    # Build preview invoice with seller data from organization
    preview_invoice = %{
      invoice
      | invoice_number: invoice_number,
        issue_date: issue_date,
        seller_display_name: organization.name,
        seller_address: organization.address,
        seller_nip: organization.nip,
        is_cash_account: invoice.payment_method == :cash
    }

    # Get currency rate for non-PLN invoices
    currency_rate = SalesInvoices.get_currency_rate(preview_invoice)

    socket
    |> assign(:organization, organization)
    |> assign(:invoice_number, invoice_number)
    |> assign(:preview_invoice, preview_invoice)
    |> assign(:currency_rate, currency_rate)
    |> assign(:series_suggestions, series_suggestions)
    |> assign(:invoice_warnings, invoice_warnings)
  end

  defp maybe_setup_step(socket, _step, _params) do
    socket
  end

  defp calculate_due_date_days(invoice) do
    if invoice.sale_date && invoice.due_date do
      Date.diff(invoice.due_date, invoice.sale_date)
    end
  end

  defp update_counterparty_stream(socket, search, no_search?, filter, sort_order) do
    counterparties = SalesInvoices.search_counterparties(search, type: filter, sort_order: sort_order)

    socket
    |> assign(
      :params,
      to_form(%{"search" => search, "filter" => filter_to_string(filter), "sort_order" => Atom.to_string(sort_order)},
        as: "search_form"
      )
    )
    |> stream(:counterparties, counterparties, reset: true)
    |> assign(:counterparties_empty?, Enum.empty?(counterparties))
    |> assign(:counterparties_zero_state?, Enum.empty?(counterparties) and no_search?)
  end

  defp filter_to_string(nil), do: ""
  defp filter_to_string(filter), do: Atom.to_string(filter)

  defp parse_tab("last_counterparties", _last_counterparties), do: :last_counterparties
  defp parse_tab("last_invoices", _last_counterparties), do: :last_invoices
  defp parse_tab(_invalid_or_nil, last_counterparties), do: default_tab(last_counterparties)

  defp default_tab([]), do: :last_invoices
  defp default_tab(_counterparties), do: :last_counterparties

  # Draft serialization/restoration

  defp serialize_to_draft(socket) do
    invoice = socket.assigns.invoice
    items = invoice.sales_invoice_items || []

    %{
      # Counterparty data (step 0)
      "counterparty_id" => invoice.counterparty_id,
      "buyer_type" => invoice.buyer_type && Atom.to_string(invoice.buyer_type),
      "buyer_id" => invoice.buyer_id,
      "buyer_full_name" => invoice.buyer_full_name,
      "buyer_given_name" => invoice.buyer_given_name,
      "buyer_surname" => invoice.buyer_surname,
      "buyer_pesel" => invoice.buyer_pesel,
      "buyer_display_name" => invoice.buyer_display_name,
      "buyer_address" => invoice.buyer_address,
      "buyer_country" => invoice.buyer_country,
      "buyer_email" => invoice.buyer_email,
      "buyer_phone" => invoice.buyer_phone,
      "buyer_description" => invoice.buyer_description,
      "invoice_type" => invoice.invoice_type && Atom.to_string(invoice.invoice_type),
      "is_reverse_charge" => invoice.is_reverse_charge,
      "currency" => invoice.currency,
      "seller_account_number" => invoice.seller_account_number,
      # Items data (step 1)
      "items" => Enum.map(items, &serialize_item/1),
      # Payment data (step 2)
      "sale_date" => invoice.sale_date && Date.to_iso8601(invoice.sale_date),
      "due_date" => invoice.due_date && Date.to_iso8601(invoice.due_date),
      "payment_method" => invoice.payment_method && Atom.to_string(invoice.payment_method)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp serialize_item(item) do
    %{
      "index" => item.index,
      "name" => item.name,
      "quantity" => item.quantity && Decimal.to_string(item.quantity),
      "unit" => item.unit,
      "unit_price" => item.unit_price && Decimal.to_string(item.unit_price),
      "vat_rate" => item.vat_rate
    }
  end

  defp restore_from_draft(socket, data, _step) do
    invoice = build_invoice_from_data(data)
    {:ok, assign(socket, :invoice, invoice)}
  rescue
    e ->
      {:error, e}
  end

  defp build_invoice_from_data(data) do
    items = Enum.map(data["items"] || [], &build_item_from_data/1)

    %SalesInvoice{
      counterparty_id: data["counterparty_id"],
      buyer_type: data["buyer_type"] && String.to_existing_atom(data["buyer_type"]),
      buyer_id: data["buyer_id"],
      buyer_full_name: data["buyer_full_name"],
      buyer_given_name: data["buyer_given_name"],
      buyer_surname: data["buyer_surname"],
      buyer_pesel: data["buyer_pesel"],
      buyer_display_name: data["buyer_display_name"],
      buyer_address: data["buyer_address"],
      buyer_country: data["buyer_country"],
      buyer_email: data["buyer_email"],
      buyer_phone: data["buyer_phone"],
      buyer_description: data["buyer_description"],
      invoice_type: data["invoice_type"] && String.to_existing_atom(data["invoice_type"]),
      is_reverse_charge: data["is_reverse_charge"] || false,
      currency: data["currency"],
      seller_account_number: data["seller_account_number"],
      sales_invoice_items: items,
      sale_date: data["sale_date"] && Date.from_iso8601!(data["sale_date"]),
      due_date: data["due_date"] && Date.from_iso8601!(data["due_date"]),
      payment_method: data["payment_method"] && String.to_existing_atom(data["payment_method"])
    }
  end

  defp build_item_from_data(data) do
    %SalesInvoiceItem{
      index: data["index"],
      name: data["name"],
      quantity: data["quantity"] && Decimal.new(data["quantity"]),
      unit: data["unit"],
      unit_price: data["unit_price"] && Decimal.new(data["unit_price"]),
      vat_rate: data["vat_rate"]
    }
  end

  defp build_copied_invoice(base_invoice, bank_accounts) do
    # Copy counterparty data from the base invoice
    counterparty_data = %{
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
      currency: base_invoice.currency
    }

    default_bank_account =
      Enum.find(bank_accounts, &(&1.is_default and &1.currency == base_invoice.currency))

    counterparty_data =
      if default_bank_account do
        Map.put(counterparty_data, :seller_account_number, default_bank_account.iban)
      else
        counterparty_data
      end

    # Build invoice with counterparty data
    invoice =
      %SalesInvoice{}
      |> SalesInvoice.step1_changeset(counterparty_data)
      |> Ecto.Changeset.apply_action!(:insert)

    # Copy items from base invoice
    copied_items =
      Enum.map(
        base_invoice.sales_invoice_items,
        &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate])
      )

    %{invoice | sales_invoice_items: Enum.map(copied_items, &struct(SalesInvoiceItem, &1))}
  end

  # Navigation helpers

  defp persist_and_navigate(socket, step, invoice) do
    socket = assign(socket, :invoice, invoice)
    draft_data = serialize_to_draft(socket)

    DraftStore.put(socket.assigns.org_id, socket.assigns.draft_id, %{
      step: step,
      data: draft_data
    })

    push_patch(socket, to: draft_url(socket.assigns.draft_id, step))
  end

  defp persist_draft(socket) do
    draft_data = serialize_to_draft(socket)

    DraftStore.put(socket.assigns.org_id, socket.assigns.draft_id, %{
      step: socket.assigns.step,
      data: draft_data
    })
  end

  defp draft_url(draft_id, step) when is_atom(step) do
    ~p"/sprzedazowe?draft=#{draft_id}&step=#{step_to_number(step)}"
  end

  # Query params management (for step 0 tabs/search)

  defp parse_search(nil), do: {nil, true}
  defp parse_search(""), do: {nil, true}
  defp parse_search(value) when is_binary(value), do: {value, false}

  defp parse_filter("company"), do: :company
  defp parse_filter("individual"), do: :individual
  defp parse_filter(_), do: nil

  defp parse_sort_order("desc"), do: :desc
  defp parse_sort_order(_), do: :asc

  defp update_counterparty_query_params(socket, updates) do
    query_params = Map.merge(socket.assigns.query_params, Map.new(updates))

    params =
      Map.merge(
        %{draft: socket.assigns.draft_id, step: step_to_number(:counterparty)},
        encode_query_params(query_params)
      )

    push_patch(socket, to: ~p"/sprzedazowe?#{params}")
  end

  def encode_query_params(query_params) do
    query_params
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @impl true
  def handle_event("validate_items", %{"sales_invoice" => params}, socket) do
    params = apply_vat_rate_from_context(params, socket.assigns.invoice)
    changeset = SalesInvoice.step2_changeset(socket.assigns.invoice, params)
    {:noreply, assign_items_form(socket, changeset)}
  end

  def handle_event("submit_items", %{"sales_invoice" => params}, socket) do
    params = apply_vat_rate_from_context(params, socket.assigns.invoice)
    old_currency = socket.assigns.invoice.currency

    result =
      socket.assigns.invoice
      |> SalesInvoice.step2_changeset(params)
      |> Ecto.Changeset.apply_action(:insert)

    case result do
      {:ok, invoice} ->
        # Reset bank account if currency changed
        invoice =
          if invoice.currency == old_currency do
            invoice
          else
            %{invoice | seller_account_number: nil}
          end

        {:noreply, persist_and_navigate(socket, :payment, invoice)}

      {:error, changeset} ->
        {:noreply, assign(socket, items_form: to_form(changeset))}
    end
  end

  def handle_event("select_counterparty", %{"counterparty_id" => counterparty_id}, socket) do
    counterparty = SalesInvoices.get_counterparty!(counterparty_id)
    tax_id_type = Counterparty.tax_id_type(counterparty)

    is_reverse_charge = reverse_charge_for_id_type?(tax_id_type)
    currency = currency_for_country(counterparty.country)
    invoice_type = invoice_type_for_country(counterparty.country)
    default_bank_account = find_default_bank_account(socket.assigns.bank_accounts, currency)

    invoice =
      socket.assigns.invoice
      |> SalesInvoice.step1_changeset(%{
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
        buyer_description: counterparty.description,
        is_reverse_charge: is_reverse_charge,
        currency: currency,
        invoice_type: invoice_type,
        seller_account_number: if(default_bank_account, do: default_bank_account.iban)
      })
      |> Ecto.Changeset.apply_action!(:insert)

    {:noreply, persist_and_navigate(socket, :items, invoice)}
  end

  def handle_event("select_base_invoice", %{"invoice_id" => invoice_id}, socket) do
    base_invoice = SalesInvoices.get_sales_invoice!(invoice_id)
    Bodyguard.permit!(SalesInvoices, :show, socket.assigns.current_user, base_invoice)

    invoice = build_copied_invoice(base_invoice, socket.assigns.bank_accounts)

    {:noreply, persist_and_navigate(socket, :items, invoice)}
  end

  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, update_counterparty_query_params(socket, tab: tab)}
  end

  def handle_event("search_counterparties", %{"search_form" => params}, socket) do
    updates = [
      search: params["search"],
      filter: parse_filter(params["filter"]),
      sort_order: parse_sort_order(params["sort_order"])
    ]

    {:noreply, update_counterparty_query_params(socket, updates)}
  end

  def handle_event("clear_counterparty_filters", _params, socket) do
    {:noreply, update_counterparty_query_params(socket, search: nil, filter: nil)}
  end

  def handle_event("validate_counterparty", %{"sales_invoice" => params}, socket) do
    form = %SalesInvoice{} |> SalesInvoice.step1_changeset(params) |> to_form(action: :validate)
    {:noreply, assign(socket, :counterparty_form, form)}
  end

  def handle_event("submit_counterparty", %{"sales_invoice" => params}, socket) do
    changeset = SalesInvoice.step1_changeset(socket.assigns.invoice, params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, invoice} ->
        buyer_id_type = SalesInvoice.buyer_id_type(invoice)
        is_reverse_charge = reverse_charge_for_id_type?(buyer_id_type)
        currency = currency_for_country(invoice.buyer_country)
        invoice_type = invoice_type_for_country(invoice.buyer_country)
        default_bank_account = find_default_bank_account(socket.assigns.bank_accounts, currency)

        invoice =
          invoice
          |> Ecto.Changeset.change(%{
            is_reverse_charge: is_reverse_charge,
            currency: currency,
            invoice_type: invoice_type,
            seller_account_number: default_bank_account && default_bank_account.iban
          })
          |> Ecto.Changeset.apply_changes()

        {:noreply, persist_and_navigate(socket, :items, invoice)}

      {:error, changeset} ->
        {:noreply, assign(socket, :counterparty_form, to_form(changeset))}
    end
  end

  def handle_event("validate_payment", %{"sales_invoice" => params}, socket) do
    form = socket.assigns.invoice |> SalesInvoice.step3_changeset(params) |> to_form(action: :validate)
    {:noreply, assign(socket, :payment_form, form)}
  end

  def handle_event("select_bank_account", %{"account_id" => account_id}, socket) do
    bank_account = Enum.find(socket.assigns.bank_accounts, &(&1.id == account_id))

    # Update invoice with selected bank account's IBAN (for draft persistence)
    invoice = %{socket.assigns.invoice | seller_account_number: bank_account.iban}

    # Preserve current form values and update the seller_account_number
    current_params = socket.assigns.payment_form.params || %{}
    updated_params = Map.put(current_params, "seller_account_number", bank_account.iban)

    form =
      invoice
      |> SalesInvoice.step3_changeset(updated_params)
      |> to_form(action: :validate)

    socket =
      socket
      |> assign(:invoice, invoice)
      |> assign(:selected_bank_account, bank_account)
      |> assign(:payment_form, form)

    # Persist to draft immediately so selection survives page refresh
    persist_draft(socket)

    {:noreply, socket}
  end

  def handle_event("submit_payment", %{"sales_invoice" => params}, socket) do
    result =
      socket.assigns.invoice
      |> SalesInvoice.step3_changeset(params)
      |> Ecto.Changeset.apply_action(:insert)

    case result do
      {:ok, invoice} ->
        # Navigate to preview step
        {:noreply, persist_and_navigate(socket, :preview, invoice)}

      {:error, changeset} ->
        {:noreply, assign(socket, payment_form: to_form(changeset))}
    end
  end

  def handle_event("update_invoice_number", %{"invoice_number" => invoice_number}, socket) do
    # Update the invoice number and rebuild the preview invoice
    preview_invoice = %{socket.assigns.preview_invoice | invoice_number: invoice_number}
    issue_date = socket.assigns.preview_invoice.issue_date

    # Validate the new invoice number
    invoice_warnings = SalesInvoices.validate_invoice_number(invoice_number, issue_date)

    {:noreply,
     socket
     |> assign(:invoice_number, invoice_number)
     |> assign(:preview_invoice, preview_invoice)
     |> assign(:invoice_warnings, invoice_warnings)}
  end

  def handle_event("select_series", %{"number" => invoice_number}, socket) do
    # User clicked a series suggestion button - set the invoice number
    preview_invoice = %{socket.assigns.preview_invoice | invoice_number: invoice_number}
    issue_date = socket.assigns.preview_invoice.issue_date

    # Validate (should be empty for suggestions, but check anyway)
    invoice_warnings = SalesInvoices.validate_invoice_number(invoice_number, issue_date)

    {:noreply,
     socket
     |> assign(:invoice_number, invoice_number)
     |> assign(:preview_invoice, preview_invoice)
     |> assign(:invoice_warnings, invoice_warnings)}
  end

  def handle_event("save_as_draft", _params, socket) do
    organization = socket.assigns.organization

    # Convert items to maps so cast_assoc processes them through changeset
    # (which sets organization_id via Repo.get_org_id())
    items_attrs =
      Enum.map(
        socket.assigns.invoice.sales_invoice_items,
        &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate])
      )

    # Clear existing items from struct so cast_assoc treats attrs as new inserts
    # (otherwise Ecto tries to match by primary key and fails on id: nil)
    invoice = %{socket.assigns.invoice | sales_invoice_items: []}

    # Insert invoice without invoice_number (draft status)
    # Set issue_date to today and populate seller data from organization
    result =
      invoice
      |> SalesInvoice.changeset(%{
        issue_date: Date.utc_today(),
        seller_display_name: organization.name,
        seller_address: organization.address,
        seller_nip: organization.nip,
        is_cash_account: invoice.payment_method == :cash,
        sales_invoice_items: items_attrs
      })
      |> Repo.insert()

    case result do
      {:ok, invoice} ->
        # Delete wizard draft
        DraftStore.delete(socket.assigns.org_id, socket.assigns.draft_id)

        {:noreply,
         socket
         |> put_flash(:info, "Faktura zapisana jako szkic")
         |> redirect(to: ~p"/sprzedazowe/#{invoice.id}")}

      {:error, changeset} ->
        Logger.error("Failed to save invoice draft: #{inspect(changeset.errors)}")

        {:noreply, put_flash(socket, :error, "Nie udało się zapisać faktury")}
    end
  end

  def handle_event("confirm_invoice", _params, socket) do
    case create_confirmed_invoice(socket) do
      {:ok, invoice} ->
        # Delete wizard draft
        DraftStore.delete(socket.assigns.org_id, socket.assigns.draft_id)

        # Navigate to summary page
        {:noreply, push_navigate(socket, to: ~p"/sprzedazowe/#{invoice.id}/podsumowanie")}

      {:error, changeset} ->
        Logger.error("Failed to confirm invoice: #{inspect(changeset.errors)}")

        error_message = get_invoice_error_message(changeset)
        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  def handle_event("send_to_ksef", _params, socket) do
    case create_confirmed_invoice(socket) do
      {:ok, invoice} ->
        # Delete wizard draft
        DraftStore.delete(socket.assigns.org_id, socket.assigns.draft_id)

        # Submit to KSeF (job will run async, Summary page will track status)
        case Ksef.submit_sales_invoice(invoice.id) do
          {:ok, _job} ->
            # Navigate to summary page - it will show sending status
            {:noreply, push_navigate(socket, to: ~p"/sprzedazowe/#{invoice.id}/podsumowanie")}

          {:error, reason} ->
            Logger.error("Failed to submit invoice to KSeF: #{inspect(reason)}")

            # Navigate to summary page with error flash
            {:noreply,
             socket
             |> put_flash(:error, "Faktura została wystawiona, ale wysyłka do KSeF nie powiodła się")
             |> push_navigate(to: ~p"/sprzedazowe/#{invoice.id}/podsumowanie")}
        end

      {:error, changeset} ->
        Logger.error("Failed to confirm invoice: #{inspect(changeset.errors)}")

        error_message = get_invoice_error_message(changeset)
        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  # Apply correct VAT rate based on buyer context.
  # - is_reverse_charge = true → force "oo" for all items
  # - EU B2B (has EU VAT ID) → force "np II"
  # - Non-EU → force "np I"
  # - Polish buyer → user selects from dropdown (no override)
  defp apply_vat_rate_from_context(params, invoice) do
    is_reverse_charge = to_boolean(params["is_reverse_charge"] || invoice.is_reverse_charge || false)
    buyer_country = invoice.buyer_country
    buyer_id_type = SalesInvoice.buyer_id_type(invoice)

    forced_rate =
      if is_reverse_charge do
        "oo"
      else
        get_fixed_vat_rate(buyer_country, buyer_id_type)
      end

    case forced_rate do
      nil ->
        # Polish buyer or EU B2C - user selects rate, apply default if empty
        apply_default_vat_rate(params)

      rate ->
        # Force VAT rate for all items
        apply_forced_vat_rate(params, rate)
    end
  end

  # Returns fixed VAT rate if buyer context allows only one option, nil otherwise
  defp get_fixed_vat_rate(buyer_country, buyer_id_type) do
    case VatRate.available_rates(buyer_country, buyer_id_type) do
      {:fixed, rate} -> rate
      {:select, _, _} -> nil
    end
  end

  defp apply_default_vat_rate(params) do
    update_in(params, ["sales_invoice_items"], fn items ->
      items
      |> items_to_list()
      |> Map.new(fn {key, item} ->
        item = if item["vat_rate"] in [nil, ""], do: Map.put(item, "vat_rate", "23"), else: item
        {key, item}
      end)
    end)
  end

  defp apply_forced_vat_rate(params, rate) do
    update_in(params, ["sales_invoice_items"], fn items ->
      items
      |> items_to_list()
      |> Map.new(fn {key, item} -> {key, Map.put(item, "vat_rate", rate)} end)
    end)
  end

  defp items_to_list(nil), do: []
  defp items_to_list(items) when is_map(items), do: Map.to_list(items)
  defp items_to_list(items) when is_list(items), do: Enum.with_index(items, fn item, idx -> {to_string(idx), item} end)

  defp get_invoice_error_message(changeset) do
    cond do
      # Organization validation errors (missing NIP, name, or address)
      Keyword.has_key?(changeset.errors, :nip) ->
        "Uzupełnij NIP firmy w ustawieniach organizacji."

      Keyword.has_key?(changeset.errors, :address) ->
        "Uzupełnij adres firmy w ustawieniach organizacji."

      Keyword.has_key?(changeset.errors, :name) ->
        "Uzupełnij nazwę firmy w ustawieniach organizacji."

      # Invoice number already taken
      match?({_, [constraint: :unique, constraint_name: _]}, Keyword.get(changeset.errors, :invoice_number, {nil, []})) ->
        "Numer faktury jest już zajęty. Zmień numer faktury i spróbuj ponownie."

      true ->
        "Nie udało się wystawić faktury"
    end
  end

  defp create_confirmed_invoice(socket) do
    organization = socket.assigns.organization

    with :ok <- validate_organization_for_invoicing(organization) do
      invoice_number = socket.assigns.invoice_number
      issue_date = Date.utc_today()

      # Convert items to maps so cast_assoc processes them through changeset
      # (which sets organization_id via Repo.get_org_id())
      items_attrs =
        Enum.map(
          socket.assigns.invoice.sales_invoice_items,
          &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate])
        )

      # Clear existing items from struct so cast_assoc treats attrs as new inserts
      # (otherwise Ecto tries to match by primary key and fails on id: nil)
      invoice = %{socket.assigns.invoice | sales_invoice_items: []}

      # Insert invoice with invoice_number and seller data from organization
      invoice
      |> SalesInvoice.changeset(%{
        invoice_number: invoice_number,
        issue_date: issue_date,
        seller_display_name: organization.name,
        seller_address: organization.address,
        seller_nip: organization.nip,
        is_cash_account: invoice.payment_method == :cash,
        is_basic_info_confirmed: true,
        is_seller_confirmed: true,
        is_buyer_confirmed: true,
        are_sales_invoice_items_confirmed: true,
        sales_invoice_items: items_attrs
      })
      |> Repo.insert()
    end
  end

  # Validates that organization has all required data for KSeF invoice submission.
  # Returns :ok if valid, {:error, changeset} with validation errors otherwise.
  defp validate_organization_for_invoicing(organization) do
    errors =
      []
      |> maybe_add_error(is_nil(organization.nip) or organization.nip == "", :nip, "NIP firmy jest wymagany")
      |> maybe_add_error(is_nil(organization.name) or organization.name == "", :name, "Nazwa firmy jest wymagana")
      |> maybe_add_error(
        is_nil(organization.address) or organization.address == "",
        :address,
        "Adres firmy jest wymagany"
      )

    if errors == [] do
      :ok
    else
      # Create a changeset-like error structure for consistent error handling
      changeset = %Ecto.Changeset{
        action: :validate,
        errors: errors,
        valid?: false,
        data: organization,
        changes: %{}
      }

      {:error, changeset}
    end
  end

  defp maybe_add_error(errors, true, field, message), do: [{field, {message, []}} | errors]
  defp maybe_add_error(errors, false, _field, _message), do: errors

  def assign_items_form(socket, changeset) do
    sales_invoice_items = Ecto.Changeset.get_assoc(changeset, :sales_invoice_items, :struct)

    single_sales_invoice_item =
      case sales_invoice_items do
        [_single_item] -> true
        _ -> false
      end

    changeset =
      case sales_invoice_items do
        [] ->
          Ecto.Changeset.put_assoc(changeset, :sales_invoice_items, [%SalesInvoiceItem{}])

        _ ->
          changeset
      end

    # Compute VAT rate options based on buyer context
    invoice = socket.assigns.invoice
    is_reverse_charge = Ecto.Changeset.get_field(changeset, :is_reverse_charge) || false
    {vat_options, vat_disabled?} = compute_vat_options(invoice, is_reverse_charge)

    socket
    |> assign(:items_form, to_form(changeset, action: :validate))
    |> assign(:summary, invoice_summary(changeset))
    |> assign(:single_item?, single_sales_invoice_item)
    |> assign(:vat_options, vat_options)
    |> assign(:vat_disabled?, vat_disabled?)
  end

  defp compute_vat_options(invoice, is_reverse_charge) do
    if is_reverse_charge do
      {VatRate.select_options_short(["oo"]), true}
    else
      buyer_id_type = SalesInvoice.buyer_id_type(invoice)

      case VatRate.available_rates(invoice.buyer_country, buyer_id_type) do
        {:select, rates, _default} -> {VatRate.select_options_short(rates), false}
        {:fixed, rate} -> {VatRate.select_options_short([rate]), true}
      end
    end
  end

  def invoice_summary(%Ecto.Changeset{} = changeset) do
    items = Ecto.Changeset.get_assoc(changeset, :sales_invoice_items, :struct)
    currency = Ecto.Changeset.get_field(changeset, :currency)

    invoice = %{sales_invoice_items: items, currency: currency}

    %{
      net_value: Money.new(currency, SalesInvoice.get_net_value(invoice)),
      vat_value: Money.new(currency, SalesInvoice.get_vat_value(invoice)),
      gross_value: Money.new(currency, SalesInvoice.get_gross_value(invoice))
    }
  end

  def to_boolean(bool) when is_boolean(bool), do: bool
  def to_boolean("true"), do: true
  def to_boolean("false"), do: false

  # Extract suggestions from invoice number warnings for display in template
  def warning_suggestions({:invalid_format, suggestions}), do: suggestions
  def warning_suggestions({:duplicate, suggestions}), do: suggestions
  def warning_suggestions({:gap, expected}), do: [expected]

  defp currency_options do
    # Use only currencies supported by NBP (plus PLN as base currency)
    nbp_currencies = Firmowid.Nbp.ApiClient.supported_currencies()
    all_supported = ["PLN" | nbp_currencies]

    popular = ["PLN", "EUR", "USD"]
    rest = all_supported -- popular

    [
      {"Popularne", popular},
      {"Wszystkie", Enum.sort(rest)}
    ]
  end

  # Find the selected bank account: first try matching IBAN, then default for currency
  defp find_selected_bank_account(bank_accounts, iban, currency) do
    Enum.find(bank_accounts, &(&1.iban == iban)) ||
      Enum.find(bank_accounts, &(&1.is_default and &1.currency == currency))
  end

  # Find a default bank account for the given currency
  defp find_default_bank_account(bank_accounts, currency) do
    Enum.find(bank_accounts, &(&1.is_default and &1.currency == currency))
  end

  # Determine if reverse charge applies based on tax ID type
  defp reverse_charge_for_id_type?(:eu_vat), do: true
  defp reverse_charge_for_id_type?(:other_id), do: true
  defp reverse_charge_for_id_type?(_), do: false

  # Determine default currency based on country
  defp currency_for_country("PL"), do: "PLN"
  defp currency_for_country(_), do: "EUR"

  # Determine invoice type based on country
  defp invoice_type_for_country("PL"), do: :poland
  defp invoice_type_for_country(_), do: :foreign

  attr :invoice, SalesInvoice, default: nil
  attr :step, :integer, required: true
  attr :title, :string, required: true

  def render_header(assigns) do
    buyer_name = assigns[:invoice] && SalesInvoices.buyer_display_name(assigns.invoice)
    assigns = assign(assigns, :buyer_name, buyer_name)

    ~H"""
    <div class="flex flex-col gap-4">
      <div class="flex flex-row gap-4 text-sm/snug text-grey-500">
        <h2>Kreator faktur | <span class="text-grey-700">Krok {@step}.</span></h2>
        <%= if @buyer_name do %>
          <p class="ml-auto">
            Kontrahent <span class="text-grey-700">{@buyer_name}</span>
          </p>
          <p>
            <%= case SalesInvoice.buyer_id_type(@invoice) do %>
              <% :nip -> %>
                NIP <span class="text-grey-700">{@invoice.buyer_id}</span>
              <% :eu_vat -> %>
                VAT-EU <span class="text-grey-700">{@invoice.buyer_id}</span>
              <% :other_id -> %>
                ID <span class="text-grey-700">{@invoice.buyer_id}</span>
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
