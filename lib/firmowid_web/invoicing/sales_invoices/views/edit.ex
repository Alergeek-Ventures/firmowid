defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Edit do
  @moduledoc """
  LiveView for editing sales invoices with live PDF preview.

  Shows the original invoice and a live preview of changes being made.
  For non-draft invoices, edits create a correction invoice (faktura korygujaca).

  Uses AshPhoenix.Form for form building and validation:
  - Drafts → `AshPhoenix.Form.for_update(invoice, :revise)`, issued through `:finalize`
  - Issued invoices, including ones issued outside KSeF → `AshPhoenix.Form.for_create(SalesInvoice, :correct)`
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents

  alias Firmowid.Core
  alias Firmowid.ErrorKind
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoice.EmailRecipientEligibility
  alias Firmowid.Invoicing.SalesInvoiceItem
  alias Firmowid.Invoicing.Services.CorrectionReason
  alias Firmowid.Ksef
  alias Firmowid.Ksef.SubmissionInfo
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Invoicing.FormHelpers
  alias FirmowidWeb.Invoicing.SalesInvoices.Components.InvoicePayment
  alias FirmowidWeb.Invoicing.SalesInvoices.Components.InvoiceReview
  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestions
  alias FirmowidWeb.Invoicing.SalesInvoices.Views.Creator
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.PriceInput

  require Logger

  embed_templates "edit_form.html"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="invoice-edit-session" phx-hook="ConfirmLeave">
      <%= if @step == :review do %>
        {draft_review(assigns)}
      <% else %>
        {edit_form(assigns)}
      <% end %>
    </div>
    """
  end

  defp draft_review(assigns) do
    ~H"""
    <InvoiceReview.invoice_review
      invoice={@preview_invoice}
      preview_invoice={@preview_invoice}
      invoice_number={@form[:invoice_number].value || ""}
      invoice_warnings={@invoice_warnings}
      invoice_number_errors={Keyword.get_values(@form.errors, :invoice_number)}
      series_suggestions={@series_suggestions}
      organization={@organization}
      currency_rate={@currency_rate}
      logo_url={@logo_url}
      counterparty_check={@counterparty_check}
      should_send_emails={@preview_invoice.should_send_emails}
      ksef_connected?={@ksef_connected?}
    >
      <:back>
        <.back
          id="back-to-edit"
          phx-click="back_to_edit"
          class="absolute inset-s-[calc(-68px-1.5rem)] inset-bs-[-2.5px]"
        />
      </:back>
      <:header>
        <Creator.render_header invoice={@invoice} step={4} title={gettext("Invoice preview")} />
      </:header>
    </InvoiceReview.invoice_review>
    """
  end

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
         |> put_flash(:error, gettext("Invoice not found"))
         |> push_navigate(to: Navigation.sales_invoice_creator_path())}

      SubmissionInfo.editing_blocked?(invoice, Ksef.get_submission_info(invoice)) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           gettext("This invoice cannot be edited — it is locked while being sent to KSeF.")
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

    socket =
      socket
      |> assign(:step, :edit)
      |> assign(:page_title, gettext("Edit invoice"))
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

    if connected?(socket) do
      event =
        if is_nil(invoice.invoice_number),
          do: :sales_invoice_edit_opened,
          else: :sales_invoice_correction_opened

      PosthogBusinessEvents.capture(socket, event)
    else
      socket
    end
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
    if is_nil(invoice.invoice_number) do
      build_update_form(invoice, scope)
    else
      build_correction_form(invoice, scope)
    end
  end

  # Draft → AshPhoenix.Form.for_update with nested items
  defp build_update_form(invoice, scope) do
    AshPhoenix.Form.for_update(invoice, :revise,
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

  # Issued invoice → AshPhoenix.Form.for_create with :correct
  defp build_correction_form(invoice, scope) do
    # For corrections of corrections, use the original (root) invoice
    original_invoice =
      if invoice.ksef_invoice_kind == :kor, do: invoice.corrected_invoice, else: invoice

    # Bare :effective_snapshot leaves attributes as %Ash.NotLoaded{}; reload them.
    original_invoice = Ash.load!(original_invoice, [:effective_snapshot], scope: scope)

    latest =
      Ash.load!(
        original_invoice.effective_snapshot,
        [
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
          :vat_exemption_type,
          :vat_exemption_basis,
          :sales_invoice_items
        ],
        scope: scope
      )

    # Pre-populate form params from the latest snapshot
    params =
      maybe_put_exemption_params(
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
                 "vat_rate" => item.vat_rate,
                 "gtu" => item.gtu
               }}
            end)
        },
        latest
      )

    AshPhoenix.Form.for_create(SalesInvoice, :correct,
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

  # Seed exemption only when the latest snapshot already has values.
  defp maybe_put_exemption_params(params, latest) do
    params
    |> maybe_put_present(
      "vat_exemption_type",
      loaded_attr(latest, :vat_exemption_type),
      &to_string/1
    )
    |> maybe_put_present("vat_exemption_basis", loaded_attr(latest, :vat_exemption_basis), & &1)
  end

  defp maybe_put_present(params, _key, nil, _transform), do: params
  defp maybe_put_present(params, _key, "", _transform), do: params

  defp maybe_put_present(params, key, value, transform) do
    Map.put(params, key, transform.(value))
  end

  defp loaded_attr(record, field) do
    case Map.get(record, field) do
      %Ash.NotLoaded{} -> nil
      value -> value
    end
  end

  @impl true
  def handle_event("add_item", %{"field" => field}, socket) do
    ash_form =
      AshPhoenix.Form.add_form(
        socket.assigns.form.source,
        String.to_existing_atom(field),
        params: %{"vat_rate" => "23", "quantity" => "1", "unit" => "szt."}
      )

    {:noreply,
     socket
     |> assign_form_with_preview(ash_form)
     |> push_event("unsaved-changed", %{value: true})}
  end

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
    # Only drafts reach this form unnumbered; an issued invoice is edited through a correction.
    if is_nil(socket.assigns.invoice.invoice_number) do
      params = socket.assigns.form.source.params || %{}

      case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
        {:ok, invoice} ->
          {:noreply,
           socket
           |> push_event("unsaved-changed", %{value: false})
           |> put_flash(:info, gettext("The invoice draft was saved."))
           |> push_navigate(to: Navigation.sales_invoice_show_path(invoice, socket.assigns.return_to))}

        {:error, form} ->
          Logger.error("Failed to save draft",
            invoice_id: socket.assigns.invoice.id,
            error_kind: ErrorKind.classify(form.source.errors)
          )

          {:noreply,
           socket
           |> assign_form_with_preview(form)
           |> put_flash(:error, gettext("Could not save the invoice."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("A correction cannot be saved as a draft."))}
    end
  end

  def handle_event("send_to_ksef", params, socket) do
    if is_nil(socket.assigns.invoice.invoice_number) and socket.assigns.step == :edit do
      prepare_draft_review(params, socket)
    else
      submit_and_send(params, socket)
    end
  end

  def handle_event("back_to_edit", _params, socket) do
    {:noreply, assign(socket, :step, :edit)}
  end

  def handle_event("update_invoice_number", %{"invoice_number" => number}, socket) do
    {:noreply, update_review_number(socket, number)}
  end

  def handle_event("select_invoice_series", %{"number" => number}, socket) do
    {:noreply, update_review_number(socket, number)}
  end

  def handle_event("update_notes", %{"invoice_note" => note, "internal_note" => comment}, socket) do
    params =
      Map.merge(socket.assigns.form.source.params, %{
        "invoice_note" => note,
        "internal_note" => comment
      })

    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign_form_with_preview(socket, form)}
  end

  def handle_event("toggle_should_send_emails", params, socket) do
    value = socket.assigns.counterparty_check.valid and params["should_send_emails"] == "true"
    params = Map.put(socket.assigns.form.source.params, "should_send_emails", value)
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign_form_with_preview(socket, form)}
  end

  defp prepare_draft_review(params, socket) do
    form_params =
      params["form"] || params["sales_invoice"] || socket.assigns.form.source.params || %{}

    gross_item_price_inputs =
      PriceInput.update_gross_value_inputs(
        socket.assigns.gross_item_price_inputs,
        form_params,
        :sales_invoice_items,
        :all
      )

    socket = assign(socket, :gross_item_price_inputs, gross_item_price_inputs)
    form_params = normalize_price_input_params(form_params)
    scope = socket.assigns.ash_scope
    issue_date = Date.utc_today()

    number =
      case form_params["invoice_number"] do
        number when number in [nil, ""] ->
          SalesInvoice.get_next_number!(issue_date, nil, socket.assigns.invoice.id, scope: scope)

        number ->
          number
      end

    form_params =
      Map.merge(form_params, %{
        "invoice_number" => number,
        "issue_date" => Date.to_iso8601(issue_date)
      })

    form = AshPhoenix.Form.validate(socket.assigns.form.source, form_params, errors: true)

    if form.valid? do
      suggestions =
        Invoicing.get_next_numbers_for_series(issue_date, [scope: scope], omit_invoice_id: socket.assigns.invoice.id)

      {:noreply,
       socket
       |> assign(:step, :review)
       |> assign(:series_suggestions, suggestions)
       |> assign_form_with_preview(form)
       |> update_review_number(number)}
    else
      {:noreply, assign_form_with_preview(socket, form)}
    end
  end

  defp update_review_number(socket, number) do
    params = Map.put(socket.assigns.form.source.params, "invoice_number", number)
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)

    warnings =
      if String.trim(number) == "" do
        []
      else
        SalesInvoice.validate_number!(
          number,
          current_issue_date(socket),
          socket.assigns.invoice.id,
          scope: socket.assigns.ash_scope
        )
      end

    socket
    |> assign_form_with_preview(form)
    |> assign(:invoice_warnings, warnings)
    |> push_event("unsaved-changed", %{value: true})
  end

  defp review_params(params, socket) do
    Map.merge(socket.assigns.form.source.params, Map.take(params, ["invoice_number"]))
  end

  defp submit_and_send(params, socket) do
    form_params =
      if socket.assigns.step == :review,
        do: review_params(params, socket),
        else: params["form"] || params["sales_invoice"] || %{}

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
    invoice = socket.assigns.invoice
    ash_form = socket.assigns.form.source
    form_params = normalize_price_input_params(form_params)

    if is_nil(invoice.invoice_number) do
      issue_draft(invoice, form_params, ash_form, socket.assigns.ash_scope)
    else
      AshPhoenix.Form.submit(ash_form, params: form_params)
    end
  end

  defp handle_submit_result({:ok, invoice}, socket) do
    {:noreply,
     socket
     |> push_event("unsaved-changed", %{value: false})
     |> push_navigate(to: Navigation.sales_invoice_summary_path(invoice, socket.assigns.return_to))}
  end

  defp handle_submit_result({:error, %AshPhoenix.Form{} = form}, socket) do
    {:noreply,
     socket
     |> assign_form_with_preview(form)
     |> put_flash(:error, gettext("Correct the errors in the form."))}
  end

  defp handle_submit_result({:error, error}, socket) do
    Logger.error("Failed to create invoice",
      invoice_id: socket.assigns.invoice.id,
      error_kind: ErrorKind.classify(error)
    )

    {:noreply, put_flash(socket, :error, get_error_message(error))}
  end

  defp issue_draft(invoice, form_params, ash_form, scope) do
    if String.trim(form_params["invoice_number"] || "") == "" do
      form =
        ash_form
        |> AshPhoenix.Form.validate(form_params, errors: true)
        |> AshPhoenix.Form.add_error(
          field: :invoice_number,
          message: gettext("Invoice number is required.")
        )

      {:error, form}
    else
      form = AshPhoenix.Form.validate(ash_form, form_params, errors: true)

      if form.valid? do
        input =
          Map.put(
            invoice_input_from_form(form),
            :invoice_number,
            String.trim(form_params["invoice_number"])
          )

        Invoicing.finalize_sales_invoice_draft(invoice, %{input: input}, scope: scope)
      else
        {:error, form}
      end
    end
  end

  defp get_error_message(_), do: gettext("Could not issue the invoice")

  # --- Shared domain preview from form values ---

  defp assign_form_with_preview(socket, ash_form) do
    phoenix_form = to_form(ash_form)
    {preview_invoice, stale?} = build_preview_from_form(ash_form, socket)

    socket
    |> assign(:form, phoenix_form)
    |> assign(:preview_invoice, preview_invoice)
    |> assign(:currency_rate, Invoicing.get_currency_rate(preview_invoice))
    |> assign(:stale_preview_invoice?, stale?)
    |> maybe_auto_fill_correction_reason()
  end

  defp build_preview_from_form(ash_form, socket) do
    invoice = socket.assigns.invoice
    input = invoice_input_from_form(ash_form)
    scope = socket.assigns.ash_scope

    result =
      if is_nil(invoice.invoice_number) do
        Invoicing.preview_sales_invoice(%{invoice: input, invoice_id: invoice.id}, scope: scope)
      else
        original = invoice.corrected_invoice || invoice

        Invoicing.preview_sales_invoice_correction(
          %{invoice: input, original_invoice_id: original.id},
          scope: scope
        )
      end

    case result do
      {:ok, preview} -> {preview, false}
      {:error, _error} -> {socket.assigns[:preview_invoice] || invoice, true}
    end
  end

  defp invoice_input_from_form(ash_form) do
    fields = Firmowid.Invoicing.Types.InvoiceInput.subtype_constraints()[:fields]

    input =
      fields
      |> Keyword.keys()
      |> List.delete(:sales_invoice_items)
      |> Map.new(fn field -> {field, AshPhoenix.Form.value(ash_form, field)} end)

    item_fields = Firmowid.Invoicing.Types.InvoiceItemInput.subtype_constraints()[:fields]

    items =
      ash_form.forms
      |> FormHelpers.access_forms(:sales_invoice_items)
      |> Enum.with_index()
      |> Enum.map(fn {form, index} ->
        item_fields
        |> Keyword.keys()
        |> Map.new(fn field -> {field, AshPhoenix.Form.value(form, field)} end)
        |> Map.put(:index, index)
      end)

    Map.put(input, :sales_invoice_items, items)
  end

  defp counterparty_check(ash_form, invoice, scope) do
    counterparty_id = AshPhoenix.Form.value(ash_form, :counterparty_id) || invoice.counterparty_id

    case EmailRecipientEligibility.fetch_valid_counterparty_email(counterparty_id, scope) do
      {:ok, _email} -> %{valid: true, tooltip: nil}
      {:error, reason, _email} -> %{valid: false, tooltip: reason}
    end
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
    if is_nil(socket.assigns.invoice.invoice_number) do
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
    if is_nil(socket.assigns.invoice.invoice_number) or socket.assigns.correction_reason_touched or
         socket.assigns.stale_preview_invoice? do
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

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

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

  defp not_editable_message(%SalesInvoice{ksef_number: nil}), do: SubmissionInfo.outside_ksef_message()

  defp not_editable_message(%SalesInvoice{ksef_invoice_kind: :vat}) do
    gettext("This invoice cannot be edited — it has corrections. Edit the latest correction.")
  end

  defp not_editable_message(%SalesInvoice{ksef_invoice_kind: :kor}) do
    gettext("This correction cannot be edited — a newer correction exists.")
  end
end
