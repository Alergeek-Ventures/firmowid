defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Creator do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing.Counterparty, as: AshCounterparty
  alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice
  alias Firmowid.Ksef
  alias Firmowid.Ksef.VatRate
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.SalesInvoices.CreatorDraftStore
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
      |> assign(:bank_accounts, Finances.list_bank_accounts!(scope: socket.assigns.ash_scope))
      |> assign(:last_counterparties, AshCounterparty.list_all!(scope: socket.assigns.ash_scope))
      |> assign(:last_invoices, AshSalesInvoice.list_recent!(scope: socket.assigns.ash_scope))
      |> assign(:ksef_connected?, Ksef.get_credential() != nil)
      |> assign(:open_counterparty_modal, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    org_id = Repo.get_org_id()

    case params do
      %{"creator_draft" => creator_draft_id} ->
        handle_existing_creator_draft(socket, org_id, creator_draft_id, params)

      %{"skopiuj" => invoice_id} ->
        create_creator_draft_from_copy(socket, org_id, invoice_id)

      _no_creator_draft ->
        create_and_redirect(socket, org_id)
    end
  end

  defp create_and_redirect(socket, org_id) do
    {:ok, creator_draft_id, _creator_draft} = CreatorDraftStore.create(org_id)
    {:noreply, push_patch(socket, to: creator_draft_url(creator_draft_id, :counterparty), replace: true)}
  end

  defp create_creator_draft_from_copy(socket, org_id, invoice_id) do
    case AshSalesInvoice.by_id(invoice_id, scope: socket.assigns.ash_scope) do
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Faktura nie została znaleziona")
         |> push_patch(to: ~p"/sprzedazowe", replace: true)}

      {:ok, base_invoice} ->
        Bodyguard.permit!(SalesInvoices, :show, socket.assigns.current_user, base_invoice)

        {:ok, creator_draft_id, _creator_draft} = CreatorDraftStore.create(org_id)

        case build_copied_invoice(base_invoice, socket.assigns.bank_accounts) do
          {:ok, invoice} ->
            socket = assign(socket, invoice: invoice, creator_draft_id: creator_draft_id, org_id: org_id)
            creator_draft_data = serialize_to_creator_draft(socket)
            CreatorDraftStore.put(org_id, creator_draft_id, %{step: :items, data: creator_draft_data})

            {:noreply, push_patch(socket, to: creator_draft_url(creator_draft_id, :items), replace: true)}

          {:partial, invoice, changeset} ->
            socket = assign(socket, invoice: invoice, creator_draft_id: creator_draft_id, org_id: org_id)
            creator_draft_data = serialize_to_creator_draft(socket)
            CreatorDraftStore.put(org_id, creator_draft_id, %{step: :counterparty, data: creator_draft_data})

            {:noreply, setup_partial_copy(socket, changeset, creator_draft_id)}
        end
    end
  end

  defp setup_partial_copy(socket, changeset, creator_draft_id) do
    # Store the failed changeset in the CreatorDraftStore so it survives the push_patch redirect.
    # We can't rely on socket assigns because push_patch re-enters handle_params
    # with the socket state from before the first handle_params call.
    org_id = socket.assigns.org_id

    CreatorDraftStore.put(org_id, creator_draft_id, %{
      step: :counterparty,
      data: serialize_to_creator_draft(socket),
      partial_copy_changeset: changeset
    })

    socket
    |> LiveToast.put_toast(
      :error,
      "Skopiowano pozycje z faktury, ale dane kontrahenta wymagają poprawy — uzupełnij formularz."
    )
    |> push_patch(to: creator_draft_url(creator_draft_id, :counterparty), replace: true)
  end

  defp handle_existing_creator_draft(socket, org_id, creator_draft_id, params) do
    # If we already have this creator draft loaded and step hasn't changed,
    # just update step-specific params (tab, search) without refetching
    current_creator_draft_id = socket.assigns[:creator_draft_id]
    current_step = socket.assigns[:step]
    requested_step = parse_step_param(params["step"])

    if current_creator_draft_id == creator_draft_id and current_step == requested_step do
      {:noreply, maybe_setup_step(socket, requested_step, params)}
    else
      fetch_and_restore_creator_draft(socket, org_id, creator_draft_id, params)
    end
  end

  defp fetch_and_restore_creator_draft(socket, org_id, creator_draft_id, params) do
    case CreatorDraftStore.get(org_id, creator_draft_id) do
      {:ok, creator_draft} ->
        restore_creator_draft(socket, org_id, creator_draft_id, creator_draft, params)

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:info, "Szkic kreatora nie został znaleziony, rozpoczynamy od nowa")
         |> push_patch(to: ~p"/sprzedazowe", replace: true)}
    end
  end

  defp restore_creator_draft(socket, org_id, creator_draft_id, creator_draft, params) do
    requested_step = parse_step_param(params["step"])
    max_allowed_step = calculate_max_step(creator_draft.data)

    # Clamp requested step to what's allowed based on data
    step = clamp_step(requested_step, max_allowed_step)

    case restore_from_creator_draft(socket, creator_draft.data, step) do
      {:ok, socket} ->
        # If this draft was created from a partial copy (invalid counterparty data),
        # pre-fill the counterparty form and auto-open the modal for the user to fix.
        socket =
          case Map.get(creator_draft, :partial_copy_changeset) do
            %Ecto.Changeset{} = changeset ->
              # Consume the changeset — remove it from the store so it doesn't re-trigger
              CreatorDraftStore.put(org_id, creator_draft_id, Map.delete(creator_draft, :partial_copy_changeset))

              socket
              |> assign(:counterparty_form, to_form(changeset, action: :validate))
              |> assign(:open_counterparty_modal, true)

            _ ->
              socket
          end

        socket =
          socket
          |> assign(:creator_draft_id, creator_draft_id)
          |> assign(:org_id, org_id)
          |> assign(:step, step)
          |> assign(:step_number, step_to_number(step))
          |> maybe_setup_step(step, params)

        # If step was clamped, redirect to correct URL
        socket =
          if step == requested_step do
            socket
          else
            push_patch(socket, to: creator_draft_url(creator_draft_id, step), replace: true)
          end

        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("Failed to restore creator draft #{creator_draft_id}: #{inspect(reason)}")
        CreatorDraftStore.delete(org_id, creator_draft_id)

        {:noreply,
         socket
         |> put_flash(:info, "Poprzedni szkic kreatora byl nieprawidlowy, rozpoczynamy od nowa")
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
    |> maybe_init_counterparty_form()
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

  # When copying an invoice with invalid counterparty data, the form is pre-filled
  # with the copied data and the modal is set to auto-open. Don't overwrite it.
  defp maybe_init_counterparty_form(%{assigns: %{open_counterparty_modal: true}} = socket) do
    socket
  end

  defp maybe_init_counterparty_form(socket) do
    assign(
      socket,
      :counterparty_form,
      %SalesInvoice{} |> SalesInvoice.step1_changeset(%{buyer_type: :company}) |> to_form()
    )
  end

  defp calculate_due_date_days(invoice) do
    if invoice.sale_date && invoice.due_date do
      Date.diff(invoice.due_date, invoice.sale_date)
    end
  end

  defp update_counterparty_stream(socket, search, no_search?, filter, sort_order) do
    counterparties =
      case AshCounterparty.search(search, filter, nil, sort_order, scope: socket.assigns.ash_scope) do
        {:ok, results} -> results
        _ -> []
      end

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

  # Creator draft serialization/restoration

  defp serialize_to_creator_draft(socket) do
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

  defp restore_from_creator_draft(socket, data, _step) do
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

    # Copy items from base invoice
    copied_items =
      base_invoice.sales_invoice_items
      |> Enum.map(&Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate]))
      |> Enum.map(&struct(SalesInvoiceItem, &1))

    # Validate counterparty data — old invoices may have data that no longer passes validation
    changeset = SalesInvoice.step1_changeset(%SalesInvoice{}, counterparty_data)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, invoice} ->
        {:ok, %{invoice | sales_invoice_items: copied_items}}

      {:error, changeset} ->
        # Counterparty data is invalid — return items-only invoice and the failed changeset
        # so the caller can land the user on the counterparty step with the modal pre-filled
        invoice = %SalesInvoice{sales_invoice_items: copied_items}
        {:partial, invoice, changeset}
    end
  end

  # Navigation helpers

  defp persist_and_navigate(socket, step, invoice) do
    socket = assign(socket, :invoice, invoice)
    creator_draft_data = serialize_to_creator_draft(socket)

    CreatorDraftStore.put(socket.assigns.org_id, socket.assigns.creator_draft_id, %{
      step: step,
      data: creator_draft_data
    })

    push_patch(socket, to: creator_draft_url(socket.assigns.creator_draft_id, step))
  end

  defp persist_creator_draft(socket) do
    creator_draft_data = serialize_to_creator_draft(socket)

    CreatorDraftStore.put(socket.assigns.org_id, socket.assigns.creator_draft_id, %{
      step: socket.assigns.step,
      data: creator_draft_data
    })
  end

  defp creator_draft_url(creator_draft_id, step) when is_atom(step) do
    ~p"/sprzedazowe?creator_draft=#{creator_draft_id}&step=#{step_to_number(step)}"
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
        %{creator_draft: socket.assigns.creator_draft_id, step: step_to_number(:counterparty)},
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
    counterparty = AshCounterparty.get!(counterparty_id, scope: socket.assigns.ash_scope)
    tax_id_type = AshCounterparty.tax_id_type(counterparty)

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
    base_invoice = AshSalesInvoice.by_id!(invoice_id, scope: socket.assigns.ash_scope)
    Bodyguard.permit!(SalesInvoices, :show, socket.assigns.current_user, base_invoice)

    case build_copied_invoice(base_invoice, socket.assigns.bank_accounts) do
      {:ok, invoice} ->
        {:noreply, persist_and_navigate(socket, :items, invoice)}

      {:partial, invoice, changeset} ->
        socket = assign(socket, :invoice, invoice)
        persist_creator_draft(socket)
        {:noreply, setup_partial_copy(socket, changeset, socket.assigns.creator_draft_id)}
    end
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

    # Update invoice with selected bank account's IBAN (for creator draft persistence)
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

    # Persist to creator draft immediately so selection survives page refresh
    persist_creator_draft(socket)

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

    # Insert invoice without invoice_number (this creates a draft/szkic)
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
        # Delete creator draft (wizard state)
        CreatorDraftStore.delete(socket.assigns.org_id, socket.assigns.creator_draft_id)

        {:noreply,
         socket
         |> put_flash(:info, "Faktura zapisana jako szkic")
         |> redirect(to: ~p"/sprzedazowe/#{invoice.id}")}

      {:error, changeset} ->
        Logger.error("Failed to save invoice as draft: #{inspect(changeset.errors)}")

        {:noreply, put_flash(socket, :error, "Nie udało się zapisać faktury")}
    end
  end

  def handle_event("confirm_invoice", _params, socket) do
    case create_confirmed_invoice(socket) do
      {:ok, invoice} ->
        # Delete creator draft (wizard state)
        CreatorDraftStore.delete(socket.assigns.org_id, socket.assigns.creator_draft_id)

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
        # Delete creator draft (wizard state)
        CreatorDraftStore.delete(socket.assigns.org_id, socket.assigns.creator_draft_id)

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
      items |> items_to_list() |> Map.new(&default_vat_rate_for_item/1)
    end)
  end

  defp default_vat_rate_for_item({key, %{"vat_rate" => rate} = item}) when rate not in [nil, ""], do: {key, item}

  defp default_vat_rate_for_item({key, item}), do: {key, Map.put(item, "vat_rate", "23")}

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

  @doc """
  Converts changeset errors to user-friendly error messages for invoice operations.
  """
  def get_invoice_error_message(changeset) do
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
        sales_invoice_items: items_attrs
      })
      |> Repo.insert()
    end
  end

  @doc """
  Validates that organization has all required data for KSeF invoice submission.
  Returns :ok if valid, {:error, changeset} with validation errors otherwise.
  """
  def validate_organization_for_invoicing(organization) do
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
    assign(socket, :items_form, to_form(changeset, action: :validate))
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
  attr :step, :any, required: true
  attr :title, :string, required: true

  def render_header(assigns) do
    buyer_name = assigns[:invoice] && AshSalesInvoice.buyer_display_name(assigns.invoice)
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
            <%= case SalesInvoice.buyer_id_type(@invoice) do %>
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
