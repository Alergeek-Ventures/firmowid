defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Edit do
  @moduledoc """
  LiveView for editing sales invoices with live PDF preview.

  Shows the original invoice and a live preview of changes being made.
  # TODO: move invoice preview/VAT summation logic to Ash calculations
  For non-draft invoices, edits create a correction invoice (faktura korygujaca).

  Uses AshPhoenix.Form for form building and validation:
  - Draft/confirmed invoices → `AshPhoenix.Form.for_update(invoice, :update)`
  - KSeF-submitted invoices → `AshPhoenix.Form.for_create(SalesInvoice, :create_correction)`
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice.EmailRecipientEligibility
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Invoicing.Services.CorrectionReason
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.SubmissionInfo
  alias FirmowidWeb.Invoicing.FormHelpers
  alias FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment
  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestions
  alias FirmowidWeb.Invoicing.SalesInvoices.Views.Creator
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.PriceInput

  require Logger

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    scope = socket.assigns.ash_scope
    return_to = Navigation.return_to_path(params["powrot_do"])

    invoice =
      case SalesInvoice.by_id(id,
             load: [
               :net_value,
               :vat_value,
               :gross_value,
               :amount,
               :is_editable,
               :buyer_id_type,
               :reference_invoice,
               sales_invoice_items: [:net_value, :vat_value, :gross_value],
               corrections: [:amount, sales_invoice_items: [:net_value, :vat_value, :gross_value]],
               corrected_invoice: [
                 :sales_invoice_items,
                 corrections: :sales_invoice_items
               ],
               latest_correction: [
                 :amount,
                 sales_invoice_items: [:net_value, :vat_value, :gross_value]
               ]
             ],
             scope: scope
           ) do
        {:ok, inv} -> inv
        {:error, _} -> nil
      end

    cond do
      is_nil(invoice) ->
        {:ok,
         socket
         |> put_flash(:error, "Nie znaleziono faktury")
         |> push_navigate(to: Navigation.sales_invoice_creator_path())}

      SubmissionInfo.editing_blocked?(invoice, Ksef.get_submission_info(invoice)) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "Nie można edytować tej faktury — jest zablokowana podczas wysyłki do KSeF."
         )
         |> push_navigate(to: Navigation.sales_invoice_show_path(invoice, return_to))}

      not invoice.is_editable ->
        {:ok,
         socket
         |> put_flash(:error, not_editable_message(invoice))
         |> push_navigate(to: Navigation.sales_invoice_show_path(invoice, return_to))}

      true ->
        {:ok, mount_editable_invoice(socket, invoice, return_to)}
    end
  end

  defp mount_editable_invoice(socket, invoice, return_to) do
    scope = socket.assigns.ash_scope
    organization = Core.get_organization!(scope.tenant, scope: scope)
    bank_accounts = Finances.list_bank_accounts!(scope: scope)

    logo_url = Invoicing.get_logo_url(invoice.organization_id, scope: scope)

    reference_invoice = load_reference_invoice(invoice, scope)

    ash_form = build_ash_form(invoice, socket.assigns.ash_scope)
    counterparty_check = counterparty_check(ash_form, invoice, scope)

    socket
    |> assign(:invoice, invoice)
    |> assign(:return_to, return_to)
    |> assign(:logo_url, logo_url)
    |> assign(:organization, organization)
    |> assign(:reference_invoice, reference_invoice)
    |> assign(:correction_reason_touched, false)
    |> assign(:last_auto_reason, "")
    |> assign(:counterparty_check, counterparty_check)
    |> assign(:item_price_input_modes, %{})
    |> assign(:gross_item_price_inputs, %{})
    |> assign(:focused_item_price_input_index, nil)
    |> assign_form_with_preview(ash_form)
    |> assign(:bank_accounts, bank_accounts)
    |> assign(
      :selected_bank_account,
      InvoicePayment.find_selected_bank_account(
        bank_accounts,
        invoice.seller_account_number,
        invoice.currency
      )
    )
    |> assign(
      :counterparties,
      Invoicing.list_counterparties!(%{status: :active}, scope: socket.assigns.ash_scope)
    )
    |> assign(:ksef_connected?, Ksef.connected?(socket.assigns.ash_scope))
  end

  defp load_reference_invoice(%{ksef_invoice_kind: :vat}, _scope), do: nil

  defp load_reference_invoice(%{ksef_invoice_kind: :kor, reference_invoice: ref}, scope) do
    case ref do
      %SalesInvoice{id: id} ->
        SalesInvoice.by_id!(id,
          load: [
            :net_value,
            :vat_value,
            :gross_value,
            :amount,
            sales_invoice_items: [:net_value, :vat_value, :gross_value]
          ],
          scope: scope
        )

      _ ->
        nil
    end
  end

  # Build AshPhoenix.Form for edit — dispatches based on invoice state
  defp build_ash_form(invoice, scope) do
    if is_nil(invoice.ksef_number) do
      build_update_form(invoice, scope)
    else
      build_correction_form(invoice, scope)
    end
  end

  # Draft or confirmed invoice → AshPhoenix.Form.for_update with nested items
  defp build_update_form(invoice, scope) do
    AshPhoenix.Form.for_update(invoice, :update,
      scope: scope,
      forms: [
        sales_invoice_items: [
          type: :list,
          resource: SalesInvoiceItem,
          create_action: :create,
          update_action: :update,
          data: invoice.sales_invoice_items || []
        ]
      ]
    )
  end

  # KSeF-submitted invoice → AshPhoenix.Form.for_create with :create_correction
  defp build_correction_form(invoice, scope) do
    # For corrections of corrections, use the original (root) invoice
    original_invoice =
      if invoice.ksef_invoice_kind == :kor, do: invoice.corrected_invoice, else: invoice

    # Get latest snapshot (most recent correction or original)
    original_invoice =
      Ash.load!(
        original_invoice,
        [
          :effective_snapshot,
          latest_correction: [
            :currency,
            :sale_date,
            :due_date,
            :payment_method,
            :seller_account_number,
            :seller_nip,
            :seller_display_name,
            :seller_address,
            :buyer_type,
            :buyer_id,
            :buyer_full_name,
            :buyer_given_name,
            :buyer_surname,
            :buyer_pesel,
            :buyer_display_name,
            :buyer_address,
            :buyer_country,
            :counterparty_id,
            :should_send_emails,
            :buyer_email,
            :buyer_phone,
            :buyer_description,
            :is_reverse_charge,
            :sales_invoice_items
          ]
        ],
        scope: scope
      )

    latest = original_invoice.effective_snapshot

    # Pre-populate form params from the latest snapshot
    params =
      %{
        "original_invoice_id" => original_invoice.id,
        "issue_date" => Date.to_iso8601(Date.utc_today()),
        "invoice_number" => SalesInvoice.get_next_number!(Date.utc_today(), "FK", nil, nil, scope: scope),
        "ksef_invoice_kind" => "kor",
        "sale_date" => if(latest.sale_date, do: Date.to_iso8601(latest.sale_date)),
        "due_date" => if(latest.due_date, do: Date.to_iso8601(latest.due_date)),
        "payment_method" => to_string(latest.payment_method),
        "currency" => latest.currency,
        "seller_account_number" => latest.seller_account_number,
        "seller_nip" => latest.seller_nip,
        "seller_display_name" => latest.seller_display_name,
        "seller_address" => latest.seller_address,
        "correction_reason" => "",
        "buyer_type" => to_string(latest.buyer_type),
        "buyer_id" => latest.buyer_id,
        "buyer_full_name" => latest.buyer_full_name,
        "buyer_given_name" => latest.buyer_given_name,
        "buyer_surname" => latest.buyer_surname,
        "buyer_pesel" => latest.buyer_pesel,
        "buyer_display_name" => latest.buyer_display_name,
        "buyer_address" => latest.buyer_address,
        "buyer_country" => latest.buyer_country,
        "buyer_email" => latest.buyer_email,
        "buyer_phone" => latest.buyer_phone,
        "buyer_description" => latest.buyer_description,
        "should_send_emails" => to_string(latest.should_send_emails || false),
        "is_reverse_charge" => to_string(latest.is_reverse_charge || false),
        "sales_invoice_items" =>
          latest.sales_invoice_items
          |> Enum.sort_by(& &1.index)
          |> Enum.with_index()
          |> Map.new(fn {item, idx} ->
            {to_string(idx),
             %{
               "index" => to_string(item.index),
               "name" => item.name,
               "quantity" => to_string(item.quantity),
               "unit" => item.unit,
               "unit_price" => to_string(item.unit_price),
               "vat_rate" => item.vat_rate
             }}
          end)
      }

    AshPhoenix.Form.for_create(SalesInvoice, :create_correction,
      scope: scope,
      params: params,
      forms: [
        sales_invoice_items: [
          type: :list,
          resource: SalesInvoiceItem,
          create_action: :create
        ]
      ]
    )
  end

  @impl true
  def handle_event("validate", params, socket) do
    # AshPhoenix.Form uses "form" as default form name
    form_params = params["form"] || params["sales_invoice"] || %{}

    gross_item_price_inputs =
      PriceInput.update_gross_value_inputs(
        socket.assigns.gross_item_price_inputs,
        form_params,
        :sales_invoice_items,
        params["_target"]
      )

    form_params = normalize_price_input_params(form_params, params["_target"])
    socket = detect_correction_reason_touched(form_params, socket)

    ash_form = AshPhoenix.Form.validate(socket.assigns.form.source, form_params)

    socket =
      socket
      |> assign_form_with_preview(ash_form)
      |> assign(:gross_item_price_inputs, gross_item_price_inputs)
      |> push_event("unsaved-changed", %{value: true})

    {:noreply, socket}
  end

  def handle_event("set_price_input_mode", %{"index" => index, "mode" => mode}, socket) do
    item_price_input_modes =
      set_price_input_mode(socket.assigns.item_price_input_modes, index, mode)

    {:noreply,
     socket
     |> assign(:item_price_input_modes, item_price_input_modes)
     |> assign(:focused_item_price_input_index, item_price_input_focus_index(index))}
  end

  def handle_event("suggest_payment_date", %{"field" => field, "suggestion" => suggestion}, socket) do
    with target when not is_nil(target) <- PaymentDateSuggestions.parse_target(field),
         suggestion_key when not is_nil(suggestion_key) <-
           PaymentDateSuggestions.parse_suggestion(suggestion) do
      issue_date = current_issue_date(socket)
      current_params = socket.assigns.form.source.params || %{}

      updated_params =
        PaymentDateSuggestions.apply_suggestion(
          current_params,
          target,
          suggestion_key,
          issue_date,
          Date.utc_today()
        )

      ash_form = AshPhoenix.Form.validate(socket.assigns.form.source, updated_params)

      {:noreply, assign_form_with_preview(socket, ash_form)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    socket =
      socket
      |> push_event("unsaved-changed", %{value: false})
      |> push_navigate(to: Navigation.sales_invoice_show_path(socket.assigns.invoice, socket.assigns.return_to))

    {:noreply, socket}
  end

  def handle_event("select_bank_account", %{"account_id" => account_id}, socket) do
    selected_account = Enum.find(socket.assigns.bank_accounts, &(&1.id == account_id))

    current_params = socket.assigns.form.source.params || %{}

    updated_params =
      if selected_account do
        Map.put(current_params, "seller_account_number", selected_account.iban)
      else
        Map.put(current_params, "seller_account_number", nil)
      end

    ash_form = AshPhoenix.Form.validate(socket.assigns.form.source, updated_params)

    {:noreply,
     socket
     |> assign(:selected_bank_account, selected_account)
     |> assign_form_with_preview(ash_form)}
  end

  def handle_event("save_as_draft", _params, socket) do
    if is_nil(socket.assigns.invoice.ksef_number) do
      case AshPhoenix.Form.submit(socket.assigns.form.source) do
        {:ok, invoice} ->
          {:noreply,
           socket
           |> push_event("unsaved-changed", %{value: false})
           |> put_flash(:info, "Wersja robocza faktury została zapisana")
           |> push_navigate(to: Navigation.sales_invoice_show_path(invoice, socket.assigns.return_to))}

        {:error, form} ->
          Logger.error("Failed to save draft: #{inspect(form.source.errors)}")
          {:noreply, put_flash(socket, :error, "Nie udało się zapisać faktury")}
      end
    else
      {:noreply, put_flash(socket, :error, "Nie można zapisać korekty jako wersji roboczej")}
    end
  end

  def handle_event("send_to_ksef", params, socket) do
    form_params = params["form"] || params["sales_invoice"] || %{}

    gross_item_price_inputs =
      PriceInput.update_gross_value_inputs(
        socket.assigns.gross_item_price_inputs,
        form_params,
        :sales_invoice_items,
        :all
      )

    socket = assign(socket, :gross_item_price_inputs, gross_item_price_inputs)

    result = submit_invoice(form_params, socket)

    handle_submit_result(result, socket)
  end

  defp submit_invoice(form_params, socket) do
    organization = socket.assigns.organization
    invoice = socket.assigns.invoice
    scope = socket.assigns.ash_scope
    ash_form = socket.assigns.form.source
    form_params = normalize_price_input_params(form_params)

    cond do
      is_nil(invoice.invoice_number) ->
        create_confirmed_invoice(organization, form_params, scope, ash_form)

      is_nil(invoice.ksef_number) ->
        update_confirmed_invoice(organization, form_params, ash_form)

      true ->
        create_correction_invoice(organization, form_params, ash_form)
    end
  end

  defp handle_submit_result({:ok, invoice}, socket) do
    if Ksef.connected?(socket.assigns.ash_scope) do
      send_invoice_to_ksef(socket, invoice)
    else
      {:noreply,
       socket
       |> push_event("unsaved-changed", %{value: false})
       |> put_flash(
         :info,
         "Faktura została wystawiona, ale nie można jej wysłać do KSeF — brak połączenia z KSeF"
       )
       |> push_navigate(to: Navigation.sales_invoice_summary_path(invoice, socket.assigns.return_to))}
    end
  end

  defp handle_submit_result({:error, %AshPhoenix.Form{} = form}, socket) do
    {:noreply,
     socket
     |> assign_form_with_preview(form)
     |> put_flash(:error, "Popraw błędy w formularzu")}
  end

  defp handle_submit_result({:error, error}, socket) do
    Logger.error("Failed to create invoice: #{inspect(error)}")

    {:noreply, put_flash(socket, :error, get_error_message(error))}
  end

  @doc false
  def send_invoice_to_ksef(socket, invoice) do
    case Ksef.submit_sales_invoice(invoice.id, socket.assigns.ash_scope) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> push_event("unsaved-changed", %{value: false})
         |> push_navigate(to: Navigation.sales_invoice_summary_path(invoice, socket.assigns.return_to))}

      {:error, reason} ->
        Logger.error("Failed to submit invoice to KSeF: #{inspect(reason)}")

        handle_failed_ksef_submission(socket, invoice, reason)
    end
  end

  defp handle_failed_ksef_submission(socket, %{ksef_invoice_kind: :kor} = invoice, reason) do
    case Ksef.cleanup_failed_correction(invoice.id, socket.assigns.ash_scope) do
      {:ok, :deleted, original_invoice_id} ->
        {:noreply,
         socket
         |> push_event("unsaved-changed", %{value: false})
         |> put_flash(:error, Ksef.failed_correction_message(reason))
         |> push_navigate(to: Navigation.sales_invoice_edit_path(original_invoice_id, socket.assigns.return_to))}

      {:error, destroy_error} ->
        Logger.error("Failed to clean up correction invoice #{invoice.id}: #{inspect(destroy_error)}")

        {:noreply,
         socket
         |> push_event("unsaved-changed", %{value: false})
         |> put_flash(:error, "Nie udało się wysłać korekty do KSeF")
         |> push_navigate(to: Navigation.sales_invoice_summary_path(invoice, socket.assigns.return_to))}

      _ ->
        # Correction already submitted or doesn't exist — shouldn't happen, fallback to summary
        {:noreply,
         socket
         |> push_event("unsaved-changed", %{value: false})
         |> put_flash(:error, "Nie udało się wysłać korekty do KSeF")
         |> push_navigate(to: Navigation.sales_invoice_summary_path(invoice, socket.assigns.return_to))}
    end
  end

  defp handle_failed_ksef_submission(socket, invoice, _reason) do
    {:noreply,
     socket
     |> push_event("unsaved-changed", %{value: false})
     |> put_flash(:error, "Faktura została wystawiona, ale wysyłka do KSeF nie powiodła się")
     |> push_navigate(to: Navigation.sales_invoice_summary_path(invoice, socket.assigns.return_to))}
  end

  defp create_confirmed_invoice(organization, form_params, scope, ash_form) do
    case Creator.validate_organization_for_invoicing(organization) do
      :ok ->
        issue_date = Date.utc_today()
        invoice_number = SalesInvoice.get_next_number!(issue_date, scope: scope)

        override_params =
          Map.merge(form_params, %{
            "invoice_number" => invoice_number,
            "issue_date" => Date.to_iso8601(issue_date),
            "seller_display_name" => organization.name,
            "seller_address" => organization.address,
            "seller_nip" => organization.nip
          })

        AshPhoenix.Form.submit(ash_form, params: override_params)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp update_confirmed_invoice(organization, form_params, ash_form) do
    case Creator.validate_organization_for_invoicing(organization) do
      :ok ->
        override_params =
          Map.merge(form_params, %{
            "seller_display_name" => organization.name,
            "seller_address" => organization.address,
            "seller_nip" => organization.nip
          })

        AshPhoenix.Form.submit(ash_form, params: override_params)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_correction_invoice(organization, form_params, ash_form) do
    case Creator.validate_organization_for_invoicing(organization) do
      :ok ->
        AshPhoenix.Form.submit(ash_form, params: form_params)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp get_error_message(_), do: "Nie udało się wystawić faktury"

  # --- Preview from form values (Option B) ---

  defp assign_form_with_preview(socket, ash_form) do
    phoenix_form = to_form(ash_form)
    preview_invoice = build_preview_from_form(ash_form, socket)

    socket
    |> assign(:form, phoenix_form)
    |> assign(:preview_invoice, preview_invoice)
    |> assign(:currency_rate, Invoicing.get_currency_rate(preview_invoice))
    |> assign(:stale_preview_invoice?, false)
    |> maybe_auto_fill_correction_reason()
  end

  defp build_preview_from_form(ash_form, socket) do
    invoice = socket.assigns.invoice
    items = build_preview_items(ash_form)
    {net_value, vat_value, gross_value} = preview_totals(items)
    ksef_invoice_kind = form_value_atom(ash_form, :ksef_invoice_kind) || invoice.ksef_invoice_kind

    preview =
      struct(
        SalesInvoice,
        ash_form
        |> build_preview_identity(invoice)
        |> Map.merge(build_preview_dates_and_payment(ash_form, invoice))
        |> Map.merge(build_preview_seller(ash_form, invoice))
        |> Map.merge(build_preview_buyer(ash_form, invoice))
        |> Map.merge(%{
          ksef_invoice_kind: ksef_invoice_kind,
          correction_reason: AshPhoenix.Form.value(ash_form, :correction_reason),
          invoice_note: AshPhoenix.Form.value(ash_form, :invoice_note),
          internal_note: AshPhoenix.Form.value(ash_form, :internal_note),
          sales_invoice_items: items,
          net_value: net_value,
          vat_value: vat_value,
          gross_value: gross_value,
          amount: Money.new(AshPhoenix.Form.value(ash_form, :currency) || invoice.currency, gross_value)
        })
      )

    maybe_attach_corrected_invoice(preview, ksef_invoice_kind, socket)
  end

  defp build_preview_items(ash_form) do
    ash_form.forms
    |> access_forms(:sales_invoice_items)
    |> Enum.with_index()
    |> Enum.map(fn {item_form, idx} ->
      quantity = parse_decimal(AshPhoenix.Form.value(item_form, :quantity)) || Decimal.new(0)
      unit_price = parse_decimal(AshPhoenix.Form.value(item_form, :unit_price)) || Decimal.new(0)
      vat_rate = to_string(AshPhoenix.Form.value(item_form, :vat_rate) || "0")
      {net_value, vat_value, gross_value} = preview_item_totals(quantity, unit_price, vat_rate)

      struct(SalesInvoiceItem,
        index: idx,
        name: AshPhoenix.Form.value(item_form, :name),
        quantity: quantity,
        unit: AshPhoenix.Form.value(item_form, :unit),
        unit_price: unit_price,
        vat_rate: vat_rate,
        net_value: net_value,
        vat_value: vat_value,
        gross_value: gross_value
      )
    end)
  end

  defp preview_item_totals(quantity, unit_price, vat_rate) do
    net_value = Decimal.mult(quantity, unit_price)
    vat_value = Decimal.mult(net_value, vat_rate_decimal(vat_rate))
    gross_value = Decimal.add(net_value, vat_value)

    {net_value, vat_value, gross_value}
  end

  defp preview_totals(items) do
    Enum.reduce(items, {Decimal.new(0), Decimal.new(0), Decimal.new(0)}, fn item, {net, vat, gross} ->
      {
        Decimal.add(net, item.net_value || Decimal.new(0)),
        Decimal.add(vat, item.vat_value || Decimal.new(0)),
        Decimal.add(gross, item.gross_value || Decimal.new(0))
      }
    end)
  end

  defp vat_rate_decimal("23"), do: Decimal.new("0.23")
  defp vat_rate_decimal("22"), do: Decimal.new("0.22")
  defp vat_rate_decimal("8"), do: Decimal.new("0.08")
  defp vat_rate_decimal("7"), do: Decimal.new("0.07")
  defp vat_rate_decimal("5"), do: Decimal.new("0.05")
  defp vat_rate_decimal("4"), do: Decimal.new("0.04")
  defp vat_rate_decimal("3"), do: Decimal.new("0.03")
  defp vat_rate_decimal(_), do: Decimal.new(0)

  defp build_preview_identity(ash_form, invoice) do
    %{
      id: invoice.id,
      organization_id: invoice.organization_id,
      invoice_number: AshPhoenix.Form.value(ash_form, :invoice_number) || invoice.invoice_number,
      invoice_type: form_value_atom(ash_form, :invoice_type) || invoice.invoice_type,
      counterparty_id: AshPhoenix.Form.value(ash_form, :counterparty_id) || invoice.counterparty_id,
      should_send_emails: parse_boolean(AshPhoenix.Form.value(ash_form, :should_send_emails)),
      is_cash_account: parse_boolean(AshPhoenix.Form.value(ash_form, :is_cash_account)),
      is_reverse_charge: parse_boolean(AshPhoenix.Form.value(ash_form, :is_reverse_charge))
    }
  end

  defp counterparty_check(ash_form, invoice, scope) do
    counterparty_id = AshPhoenix.Form.value(ash_form, :counterparty_id) || invoice.counterparty_id

    case EmailRecipientEligibility.fetch_valid_counterparty_email(counterparty_id, scope) do
      {:ok, _email} -> %{valid: true, tooltip: nil}
      {:error, reason, _email} -> %{valid: false, tooltip: reason}
    end
  end

  defp build_preview_dates_and_payment(ash_form, invoice) do
    %{
      issue_date: form_value_date(ash_form, :issue_date) || invoice.issue_date,
      sale_date: form_value_date(ash_form, :sale_date) || invoice.sale_date,
      due_date: form_value_date(ash_form, :due_date) || invoice.due_date,
      payment_method: form_value_atom(ash_form, :payment_method) || invoice.payment_method,
      currency: AshPhoenix.Form.value(ash_form, :currency) || invoice.currency
    }
  end

  defp build_preview_seller(ash_form, invoice) do
    %{
      seller_nip: AshPhoenix.Form.value(ash_form, :seller_nip) || invoice.seller_nip,
      seller_display_name: AshPhoenix.Form.value(ash_form, :seller_display_name) || invoice.seller_display_name,
      seller_address: AshPhoenix.Form.value(ash_form, :seller_address) || invoice.seller_address,
      seller_account_number: AshPhoenix.Form.value(ash_form, :seller_account_number) || invoice.seller_account_number
    }
  end

  defp build_preview_buyer(ash_form, invoice) do
    %{
      buyer_type: form_value_atom(ash_form, :buyer_type) || invoice.buyer_type,
      buyer_id: AshPhoenix.Form.value(ash_form, :buyer_id),
      buyer_full_name: AshPhoenix.Form.value(ash_form, :buyer_full_name),
      buyer_given_name: AshPhoenix.Form.value(ash_form, :buyer_given_name),
      buyer_surname: AshPhoenix.Form.value(ash_form, :buyer_surname),
      buyer_pesel: AshPhoenix.Form.value(ash_form, :buyer_pesel),
      buyer_display_name: AshPhoenix.Form.value(ash_form, :buyer_display_name),
      buyer_address: AshPhoenix.Form.value(ash_form, :buyer_address),
      buyer_country: AshPhoenix.Form.value(ash_form, :buyer_country) || invoice.buyer_country,
      buyer_email: AshPhoenix.Form.value(ash_form, :buyer_email),
      buyer_phone: AshPhoenix.Form.value(ash_form, :buyer_phone),
      buyer_description: AshPhoenix.Form.value(ash_form, :buyer_description)
    }
  end

  defp maybe_attach_corrected_invoice(preview, :kor, socket) do
    original_invoice = socket.assigns.invoice.corrected_invoice || socket.assigns.invoice
    reference = socket.assigns[:reference_invoice]

    preview
    |> Map.put(:corrected_invoice, original_invoice)
    |> Map.put(:reference_invoice, reference)
  end

  defp maybe_attach_corrected_invoice(preview, _kind, _socket), do: preview

  defp form_value_atom(ash_form, field) do
    ash_form |> AshPhoenix.Form.value(field) |> parse_atom()
  end

  defp form_value_date(ash_form, field) do
    ash_form |> AshPhoenix.Form.value(field) |> parse_date()
  end

  defp current_issue_date(socket) do
    form_value_date(socket.assigns.form.source, :issue_date) ||
      socket.assigns.invoice.issue_date ||
      Date.utc_today()
  end

  # --- Correction reason auto-generation ---

  defp detect_correction_reason_touched(params, socket) do
    if is_nil(socket.assigns.invoice.ksef_number) do
      socket
    else
      user_reason = Map.get(params, "correction_reason", "")
      last_auto = socket.assigns.last_auto_reason

      if user_reason != last_auto and user_reason != "" do
        assign(socket, :correction_reason_touched, true)
      else
        socket
      end
    end
  end

  defp maybe_auto_fill_correction_reason(socket) do
    if is_nil(socket.assigns.invoice.ksef_number) or socket.assigns.correction_reason_touched do
      sync_user_reason_to_preview(socket)
    else
      auto_fill_correction_reason(socket)
    end
  end

  defp sync_user_reason_to_preview(socket) do
    preview = socket.assigns[:preview_invoice]
    form_reason = AshPhoenix.Form.value(socket.assigns.form.source, :correction_reason)

    if preview && form_reason do
      assign(socket, :preview_invoice, Map.put(preview, :correction_reason, form_reason))
    else
      socket
    end
  end

  defp auto_fill_correction_reason(socket) do
    reference = socket.assigns[:reference_invoice] || socket.assigns.invoice
    preview = socket.assigns[:preview_invoice]

    auto_reason =
      if preview do
        CorrectionReason.generate(preview, reference)
      else
        ""
      end

    ash_form = socket.assigns.form.source
    current_params = ash_form.params || %{}
    updated_params = Map.put(current_params, "correction_reason", auto_reason)
    updated_form = AshPhoenix.Form.validate(ash_form, updated_params)

    socket
    |> assign(:last_auto_reason, auto_reason)
    |> assign(:preview_invoice, Map.put(preview, :correction_reason, auto_reason))
    |> assign(:form, to_form(updated_form))
  end

  # --- Helpers ---

  defp access_forms(forms, key), do: FormHelpers.access_forms(forms, key)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_atom(nil), do: nil
  defp parse_atom(""), do: nil
  defp parse_atom(a) when is_atom(a), do: a
  defp parse_atom(s) when is_binary(s), do: String.to_existing_atom(s)

  defp parse_boolean(nil), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(_), do: false

  defp parse_decimal(value), do: FormHelpers.parse_decimal(value)

  defp normalize_price_input_params(params, target \\ :all) do
    indexes = PriceInput.gross_value_indexes(params, :sales_invoice_items, target)

    PriceInput.normalize_gross_value_params(
      params,
      :sales_invoice_items,
      &parse_decimal/1,
      indexes
    )
  end

  defp set_price_input_mode(_item_price_input_modes, "all", mode), do: %{"all" => mode}

  defp set_price_input_mode(item_price_input_modes, item_index, mode) do
    Map.put(item_price_input_modes, item_index, mode)
  end

  defp item_price_input_focus_index("all"), do: nil
  defp item_price_input_focus_index(item_index), do: item_index

  defp not_editable_message(%SalesInvoice{ksef_invoice_kind: :vat}) do
    "Nie można edytować tej faktury — posiada korekty. Edytuj ostatnią korektę."
  end

  defp not_editable_message(%SalesInvoice{ksef_invoice_kind: :kor}) do
    "Nie można edytować tej korekty — istnieje nowsza korekta."
  end
end
