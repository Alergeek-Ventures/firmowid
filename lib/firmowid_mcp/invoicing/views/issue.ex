defmodule FirmowidMcp.Invoicing.Views.Issue do
  @moduledoc "User-confirmed invoice and correction issuance, with the existing asynchronous KSeF lifecycle."
  use FirmowidMcp, :live_view

  import FirmowidUI.Components.Button
  import Phoenix.Component

  alias AshPhoenix.FormData.Error
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.SubmissionInfo
  alias FirmowidMcp.Invoicing.IssueCorrection
  alias FirmowidMcp.Invoicing.IssueInvoice
  alias FirmowidMcp.LiveSession
  alias FirmowidMcp.Widgets
  alias FirmowidUI.Invoicing.Components.InvoiceNumber
  alias FirmowidUI.Invoicing.Components.SalesInvoice, as: InvoicePreview

  @invoice_loads [
    :buyer_id_type,
    :corrected_invoice,
    :net_value,
    :vat_value,
    :gross_value,
    :amount,
    reference_invoice:
      {%{},
       [
         :amount,
         :net_value,
         :vat_value,
         :gross_value,
         :buyer_id_type,
         sales_invoice_items: [:net_value, :vat_value, :gross_value]
       ]},
    sales_invoice_items: [:net_value, :vat_value, :gross_value]
  ]
  @review_fields [
    :invoice_type,
    :issue_date,
    :sale_date,
    :due_date,
    :currency,
    :payment_method,
    :seller_nip,
    :seller_display_name,
    :seller_address,
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
    :is_reverse_charge,
    :vat_exemption_type,
    :vat_exemption_basis,
    :invoice_note,
    :correction_reason,
    :correction_type
  ]

  @impl true
  def mount(_params, session, socket) do
    widget = Widgets.for_resource(session["mcp_resource"])

    socket =
      assign(socket,
        widget: widget,
        invoice: nil,
        currency_rate: nil,
        issued_id: nil,
        phase: :review,
        connection: nil,
        invoice_number: "",
        invoice_warnings: [],
        next_numbers_by_series: %{},
        errors: [],
        submission_info: nil,
        show_vat: true,
        footer_logo_url: FirmowidMcp.endpoint().url() <> "/images/invoice_firmowid_logo.png"
      )

    LiveSession.mount(session, socket, widget,
      on_mount: &load_review/1,
      on_expire: &clear/1
    )
  end

  @impl true
  def handle_event(event, params, socket) do
    LiveSession.handle_event(event, params, socket, &handle_interaction/3)
  end

  defp handle_interaction("update_invoice_number", %{"invoice_number" => number}, socket)
       when socket.assigns.phase == :review do
    {:noreply, select_number(socket, number)}
  end

  defp handle_interaction("select_invoice_series", %{"number" => number}, socket) when socket.assigns.phase == :review do
    {:noreply, select_number(socket, number)}
  end

  defp handle_interaction("confirm_issuance", _params, %{assigns: %{phase: :review, invoice: invoice}} = socket)
       when not is_nil(invoice) do
    {:noreply, confirm(socket)}
  end

  defp handle_interaction("refresh_invoice_status", _params, socket) do
    {:noreply, if(socket.assigns.issued_id, do: refresh_issued(socket), else: load_review(socket))}
  end

  defp handle_interaction("retry_ksef_submission", _params, %{assigns: %{phase: phase, issued_id: id}} = socket)
       when phase in [:failed, :not_submitted] and not is_nil(id) do
    scope = socket.assigns.scope

    with {:ok, true} <-
           Ash.can({SalesInvoice, :issue_invoice, %{input: %{}}}, scope, maybe_is: false),
         {:ok, %{status: :connected}} <- Ksef.connection_status(scope: scope),
         {:ok, _job} <- Ksef.submit_sales_invoice(id, scope) do
      {:noreply, refresh_issued(socket)}
    else
      _failure ->
        {:noreply, assign(socket, :errors, [gettext("Unable to start KSeF submission. Try again.")])}
    end
  end

  defp handle_interaction(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:ksef_invoice_status, %{invoice_id: id, status: status}} = message, socket) do
    LiveSession.handle_info(message, socket, fn _message, socket ->
      socket =
        if socket.assigns.issued_id == id do
          if status == :failed and socket.assigns.widget == IssueCorrection,
            do: cleanup_failed_correction(socket),
            else: refresh_issued(socket)
        else
          socket
        end

      {:noreply, socket}
    end)
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_review(socket) do
    scope = socket.assigns.scope

    with {:ok, connection} <- Ksef.connection_status(scope: scope),
         {:ok, organization} <- Core.get_organization(scope.tenant, scope: scope),
         {:ok, existing} <- existing_confirmation(socket) do
      socket =
        assign(socket, connection: connection, show_vat: organization.is_vat_payer, errors: [])

      if connected?(socket), do: Ksef.subscribe_ksef_status(scope.tenant)

      case existing do
        nil -> load_preview(socket)
        :deleted -> deleted(socket)
        invoice -> display_issued(socket, invoice)
      end
    else
      {:error, _reason} ->
        assign(socket,
          invoice: nil,
          currency_rate: nil,
          errors: [gettext("Unable to load the invoice preview. Try again.")]
        )
    end
  end

  defp existing_confirmation(socket) do
    id = action_arguments(socket)["invoice_id"] || socket.assigns.confirmation_id

    case Invoicing.get_sales_invoice(id,
           scope: socket.assigns.scope,
           load: @invoice_loads,
           not_found_error?: false
         ) do
      {:ok, %{invoice_number: number} = invoice} when not is_nil(number) -> {:ok, invoice}
      {:ok, _draft_or_missing} -> previous_attempt(socket)
      {:error, reason} -> {:error, reason}
    end
  end

  defp previous_attempt(socket) do
    # A deleted correction may still have its terminal submission job. Reopening
    # the same signed confirmation must not create the correction a second time.
    info = Ksef.get_submission_info(%{id: socket.assigns.confirmation_id})
    {:ok, if(SubmissionInfo.attempted?(info), do: :deleted)}
  end

  defp load_preview(socket) do
    with {:ok, _result, invoice} <-
           Widgets.execute(socket.assigns.widget, socket.assigns.arguments, socket.assigns.scope),
         {:ok, next_number} <-
           SalesInvoice.get_next_number(
             invoice.issue_date,
             series(socket),
             action_arguments(socket)["invoice_id"],
             scope: socket.assigns.scope
           ) do
      number = invoice.invoice_number || next_number

      socket
      |> assign(
        invoice: invoice,
        currency_rate: Invoicing.get_currency_rate(invoice),
        invoice_number: number,
        next_numbers_by_series:
          Invoicing.get_next_numbers_for_series(invoice.issue_date, [scope: socket.assigns.scope],
            omit_invoice_id: action_arguments(socket)["invoice_id"]
          ),
        phase: :review,
        errors: []
      )
      |> select_number(number)
      |> publish_context()
    else
      {:error, error} ->
        assign(socket, invoice: nil, currency_rate: nil, errors: error_messages(error))
    end
  end

  defp series(%{assigns: %{widget: IssueCorrection}}), do: "FK"
  defp series(_socket), do: nil

  defp select_number(%{assigns: %{invoice: nil}} = socket, _number), do: socket

  defp select_number(socket, number) do
    number = String.trim(number)

    assign(socket,
      invoice_number: number,
      invoice_warnings: number_warnings(socket, number),
      invoice: %{socket.assigns.invoice | invoice_number: number},
      errors: []
    )
  end

  defp number_warnings(_socket, ""), do: []

  defp number_warnings(socket, number) do
    SalesInvoice.validate_number!(
      number,
      socket.assigns.invoice.issue_date,
      action_arguments(socket)["invoice_id"],
      scope: socket.assigns.scope
    )
  end

  defp confirm(socket) do
    with {:ok, %{status: :connected} = connection} <-
           Ksef.connection_status(scope: socket.assigns.scope),
         {:ok, _result, current} <-
           Widgets.execute(socket.assigns.widget, socket.assigns.arguments, socket.assigns.scope) do
      socket = assign(socket, :connection, connection)

      if review_snapshot(current) == review_snapshot(socket.assigns.invoice) do
        issue(socket)
      else
        socket
        |> load_preview()
        |> assign(:errors, [
          gettext("The invoice data changed. Review the updated preview and confirm again.")
        ])
      end
    else
      {:ok, connection} ->
        assign(socket,
          connection: connection,
          errors: [gettext("Connect KSeF before issuing the invoice.")]
        )

      {:error, error} ->
        assign(socket, :errors, error_messages(error))
    end
  end

  defp issue(socket) do
    case issue_document(socket) do
      {:ok, invoice} ->
        case Ash.Resource.get_metadata(invoice, :ksef_submission_error) do
          nil ->
            socket |> assign(:issued_id, invoice.id) |> refresh_issued()

          _reason ->
            socket
            |> assign(:issued_id, invoice.id)
            |> refresh_issued()
            |> assign(:errors, [gettext("Unable to start KSeF submission. Try again.")])
        end

      {:error, error} ->
        recover_confirmation(socket, error)
    end
  end

  defp issue_document(%{assigns: %{widget: IssueInvoice}} = socket) do
    Invoicing.issue_sales_invoice(
      %{
        input: confirmed_input(socket),
        invoice_id: action_arguments(socket)["invoice_id"],
        confirmation_id: socket.assigns.confirmation_id,
        submit_to_ksef: true
      },
      scope: socket.assigns.scope
    )
  end

  defp issue_document(%{assigns: %{widget: IssueCorrection}} = socket) do
    Invoicing.issue_sales_invoice_correction(
      %{
        input: confirmed_input(socket),
        original_invoice_id: action_arguments(socket)["original_invoice_id"],
        confirmation_id: socket.assigns.confirmation_id,
        submit_to_ksef: true
      },
      scope: socket.assigns.scope
    )
  end

  defp confirmed_input(socket) do
    attrs = action_arguments(socket)["input"] || %{}

    attrs
    |> Map.put("invoice_number", socket.assigns.invoice_number)
    |> Map.put("issue_date", Date.to_iso8601(socket.assigns.invoice.issue_date))
  end

  defp recover_confirmation(socket, error) do
    case existing_confirmation(socket) do
      {:ok, %{invoice_number: number} = invoice} when not is_nil(number) ->
        display_issued(socket, invoice)

      {:ok, :deleted} ->
        deleted(socket)

      _ ->
        assign(socket, :errors, error_messages(error))
    end
  end

  defp action_arguments(socket), do: socket.assigns.arguments["input"] || %{}

  defp refresh_issued(socket) do
    case Invoicing.get_sales_invoice(socket.assigns.issued_id,
           scope: socket.assigns.scope,
           load: @invoice_loads,
           not_found_error?: false
         ) do
      {:ok, nil} ->
        deleted(socket)

      {:ok, invoice} ->
        display_issued(socket, invoice)

      {:error, _reason} ->
        assign(socket, :errors, [gettext("Unable to refresh the invoice status. Try again.")])
    end
  end

  defp display_issued(socket, invoice) do
    info = Ksef.get_submission_info(invoice)

    socket
    |> assign(
      invoice: invoice,
      currency_rate: Invoicing.get_currency_rate(invoice),
      issued_id: invoice.id,
      phase: info.status,
      submission_info: info,
      errors: []
    )
    |> publish_context()
  end

  defp cleanup_failed_correction(socket) do
    case Ksef.cleanup_failed_correction(socket.assigns.issued_id, socket.assigns.scope) do
      {:ok, :deleted, _source_id} -> deleted(socket)
      {:ok, :not_found} -> deleted(socket)
      _other -> refresh_issued(socket)
    end
  end

  defp deleted(socket) do
    socket
    |> assign(invoice: nil, currency_rate: nil, phase: :deleted, errors: [])
    |> publish_context()
  end

  defp publish_context(socket) do
    invoice = socket.assigns.invoice

    push_event(socket, "mcp:context", %{
      structuredContent: %{
        state: socket.assigns.phase,
        invoice_id: socket.assigns.issued_id,
        invoice_number: if(invoice, do: invoice.invoice_number),
        ksef_number: if(invoice, do: invoice.ksef_number),
        requires_confirmation: socket.assigns.phase == :review
      }
    })
  end

  defp review_snapshot(invoice) do
    items =
      Enum.map(
        invoice.sales_invoice_items,
        &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate])
      )

    invoice
    |> Map.take(@review_fields)
    |> Map.put(:items, items)
    |> Map.put(:reference_invoice, reference_snapshot(invoice.reference_invoice))
  end

  defp reference_snapshot(nil), do: nil
  defp reference_snapshot(%Ash.NotLoaded{}), do: nil

  defp reference_snapshot(invoice) when is_map(invoice) do
    invoice
    |> Map.take([:id, :invoice_number, :ksef_number, :amount])
    |> Map.put(
      :sales_invoice_items,
      Enum.map(
        invoice.sales_invoice_items,
        &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate])
      )
    )
  end

  defp error_messages(%{errors: errors}) do
    errors
    |> Enum.flat_map(&form_errors/1)
    |> case do
      [] -> [gettext("Unable to issue the invoice. Check its details and try again.")]
      messages -> messages
    end
  end

  defp error_messages(error), do: error |> Ash.Error.to_error_class() |> error_messages()

  defp form_errors(error) do
    if Error.impl_for(error) do
      error
      |> Error.to_form_error()
      |> List.wrap()
      |> Enum.map(fn {_field, message, bindings} -> translate_error({message, bindings}) end)
    else
      []
    end
  end

  defp clear(socket),
    do: assign(socket, invoice: nil, currency_rate: nil, connection: nil, errors: [], submission_info: nil)

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="mcp-invoice-issuance"
      phx-hook="McpContext"
      class="grid gap-4 p-4 min-inline-0"
      phx-disconnected={JS.set_attribute({"inert", ""})}
      phx-connected={JS.remove_attribute("inert")}
    >
      <h1 class="text-lg font-semibold">
        {if @widget == IssueCorrection,
          do: gettext("Confirm invoice correction"),
          else: gettext("Confirm invoice")}
      </h1>
      <p :if={@status == :expired} role="status">{gettext("This view is unavailable.")}</p>
      <p :for={error <- @errors} role="alert" class="text-red-700">{error}</p>
      <%= if @status == :ready do %>
        <p :if={(@phase == :review and @connection) && @connection.status != :connected} role="status">
          {gettext("Connect KSeF before issuing the invoice.")}
        </p>
        <%= if @invoice do %>
          <InvoiceNumber.invoice_number
            :if={@phase == :review}
            invoice_number={@invoice_number}
            next_numbers_by_series={@next_numbers_by_series}
            warnings={@invoice_warnings}
          />
          <div id="invoice-preview" class="overflow-x-auto bg-white" tabindex="0">
            <InvoicePreview.sales_invoice
              sales_invoice={@invoice}
              currency_rate={@currency_rate}
              show_vat={@show_vat}
              reference_invoice={@invoice.reference_invoice}
              footer_logo_data_uri={@footer_logo_url}
            />
          </div>
          <.button
            :if={@phase == :review}
            id="confirm-invoice-issuance"
            type="button"
            variant="primary"
            accent="turquoise"
            phx-click="confirm_issuance"
            phx-disable-with={gettext("Issuing…")}
            disabled={
              not @connected? or is_nil(@connection) or @connection.status != :connected or
                @invoice_number == ""
            }
            class="justify-self-start outline-offset-2 focus-visible:outline-2 active:opacity-80 disabled:opacity-50"
          >
            {gettext("Confirm and send to KSeF")}
          </.button>
        <% end %>
        <p id="invoice-submission-status" role="status" aria-live="polite">
          {status_message(@phase)}
        </p>
        <p :if={@phase == :submitted and @invoice} class="wrap-break-word">{@invoice.ksef_number}</p>
        <p :if={(@phase == :failed and @submission_info) && @submission_info.error} role="alert">
          {@submission_info.error}
        </p>
        <div class="flex flex-wrap gap-2">
          <.button
            id="refresh-invoice-status"
            type="button"
            variant="outline"
            size="small"
            phx-click="refresh_invoice_status"
            class="outline-offset-2 focus-visible:outline-2 active:opacity-80"
          >
            {gettext("Refresh")}
          </.button>
          <.button
            :if={@phase in [:failed, :not_submitted] and @issued_id}
            id="retry-invoice-submission"
            type="button"
            variant="outline"
            size="small"
            phx-click="retry_ksef_submission"
            phx-disable-with={gettext("Sending…")}
            class="outline-offset-2 focus-visible:outline-2 active:opacity-80"
          >
            {gettext("Retry KSeF submission")}
          </.button>
        </div>
      <% end %>
    </section>
    """
  end

  defp status_message(:review), do: gettext("Nothing has been issued yet. Review the preview before confirming.")

  defp status_message(:submitting), do: gettext("The invoice is saved. Sending to KSeF…")
  defp status_message(:submitted), do: gettext("KSeF accepted the invoice.")
  defp status_message(:failed), do: gettext("The invoice is saved, but KSeF submission failed.")

  defp status_message(:not_submitted), do: gettext("The invoice is saved, but KSeF submission has not started.")

  defp status_message(:deleted),
    do: gettext("The correction could not be sent and was removed. Prepare a new correction after fixing its details.")
end
