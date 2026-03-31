defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Summary do
  @moduledoc """
  LiveView for displaying the summary page after a sales invoice has been created.

  This page shows the invoice details and KSeF submission status, allowing users to:
  - View the created invoice
  - Monitor KSeF submission progress
  - Navigate to edit the invoice or create a new one
  """
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice
  alias Firmowid.Ksef
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user

    scope = socket.assigns.ash_scope
    invoice = AshSalesInvoice.by_id!(id, scope: scope)

    Bodyguard.permit!(SalesInvoices, :show, current_user, invoice)

    submission_info = Ksef.get_submission_info(invoice)

    # Subscribe to KSeF status updates if submission is in progress
    if submission_info.status == :submitting do
      Ksef.subscribe_ksef_status(current_user.organization_id)
    end

    currency_rate = AshSalesInvoice.get_currency_rate(invoice)

    {previous_invoices, invoice} = get_previous_invoices(invoice)

    socket =
      socket
      |> assign(:invoice, invoice)
      |> assign(:previous_invoices, previous_invoices)
      |> assign(:submission_info, submission_info)
      |> assign(:currency_rate, currency_rate)
      |> assign(:ksef_connected?, Ksef.get_credential() != nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto my-4 flex w-full max-w-6xl flex-col gap-4">
      <p class="text-grey-500 text-sm">
        Kreator faktur | <span class="text-grey-700">Faktura wystawiona</span>
      </p>
      <%= case @submission_info.status do %>
        <% :submitting -> %>
          <h1 class="flex items-baseline gap-1 text-[27px]/tight font-medium">
            Faktura w trakcie wysyłania
            <span class="inline-flex gap-1">
              <span class="bg-grey-400 size-1.5 animate-bounce rounded-full [animation-delay:-0.3s]">
              </span>
              <span class="bg-grey-400 size-1.5 animate-bounce rounded-full [animation-delay:-0.15s]">
              </span>
              <span class="bg-grey-400 size-1.5 animate-bounce rounded-full"></span>
            </span>
          </h1>
        <% :submitted -> %>
          <h1 class="text-[27px]/tight font-medium">Faktura wysłana do KSeF</h1>
        <% :failed -> %>
          <h1 class="text-[27px]/tight font-medium text-red-600">
            Wysyłka do KSeF nie powiodła się
          </h1>
        <% _ -> %>
          <h1 class="text-[27px]/tight font-medium">Faktura wystawiona</h1>
      <% end %>

      <div class="flex items-center justify-between">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/sprzedazowe/#{@invoice.id}/edytuj"}
            class={button_styles(%{size: "small", color: "light_grey", new: true})}
          >
            <Lucideicons.pencil /> Edytuj
          </.link>
          <.link
            href={~p"/sprzedazowe/#{@invoice.id}/pobierz"}
            class={button_styles(%{size: "small", color: "light_grey", new: true})}
          >
            <Lucideicons.download /> Pobierz
          </.link>
          <.button
            :if={
              @ksef_connected? and SalesInvoice.confirmed?(@invoice) and
                @submission_info.status in [:not_submitted, :failed]
            }
            color="light_grey"
            size="small"
            new={true}
            phx-click="send_to_ksef"
          >
            <Lucideicons.send /> Wyślij do KSeF
          </.button>
        </div>

        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/sprzedazowe/#{@invoice.id}"}
            class="hover:text-grey-900 text-grey-600 text-sm"
          >
            Przejdź do faktury
          </.link>
          <.link
            navigate={~p"/sprzedazowe"}
            class={button_styles(%{size: "medium", color: "turquoise", new: true})}
          >
            Wystaw kolejną
          </.link>
        </div>
      </div>
      <%= if @submission_info.status == :failed do %>
        <div class="bg-redBg text-redText flex flex-col items-center justify-center gap-4 rounded-md p-8 text-center">
          <Lucideicons.triangle_alert class="size-10 text-red-600" />
          <h2 class="text-xl">Wysyłka do KSeF nie powiodła się.</h2>
          <p :if={@submission_info.error} class="max-w-lg text-sm">
            {@submission_info.error}
          </p>
          <p class="text-grey-600 mt-2 text-sm">
            Edytuj fakturę, aby ponowić wysyłkę.
          </p>
          <.link
            navigate={~p"/sprzedazowe/#{@invoice.id}"}
            class={[
              "bg-turquoise hover:bg-turquoise/90 mt-4 flex items-center gap-2 rounded-md px-4 py-2 text-white transition-colors"
            ]}
          >
            <Lucideicons.pencil class="size-4" /> Przejdź do faktury
          </.link>
        </div>
      <% end %>

      <div class="invisible h-8" />

      <div class="grid grid-cols-[1fr_650px_1fr] items-start justify-center gap-8">
        <% list_width = 224 %>
        <% template_width = 595 %>
        <% template_height = 842 %>
        <% scale = list_width / template_width %>

        <div class="space-y-6" style={"width: #{list_width}px;"}>
          <div
            :for={previous_invoice <- @previous_invoices}
            class="space-y-2"
          >
            <p class="text-grey-700 pl-1 text-sm/tight">
              {previous_invoice.invoice_number}
            </p>
            <div
              class="border-grey-200 overflow-hidden rounded-lg border bg-white shadow-sm"
              style={"width: #{template_width * scale}px; height: #{template_height * scale}px;"}
            >
              <div class="origin-top-left" style={"transform: scale(#{scale})"}>
                <FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice
                  sales_invoice={previous_invoice}
                  currency_rate={@currency_rate}
                  show_vat={@current_org.is_vat_payer}
                  reference_invoice={previous_invoice.reference_invoice}
                />
              </div>
            </div>
          </div>
        </div>

        <div class="relative">
          <%!-- Success state - behind invoice (z-0) --%>
          <div class="absolute inset-0 z-0 flex items-center justify-center">
            <div class="text-center">
              <Lucideicons.circle_check class="text-greenText mx-auto size-24" />
              <p class="text-grey-700 mt-4 text-xl font-medium">Wysłano do KSeF!</p>
            </div>
          </div>

          <%!-- Invoice preview - above success (z-10) --%>
          <div
            id="invoice-preview"
            phx-hook="PaperPlane"
            class="relative z-10"
          >
            <div class="border-grey-200 w-full max-w-[650px] overflow-hidden rounded-lg border bg-white shadow-sm">
              <FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice
                sales_invoice={@invoice}
                currency_rate={@currency_rate}
                show_vat={@current_org.is_vat_payer}
                reference_invoice={@invoice.reference_invoice}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("send_to_ksef", _params, socket) do
    invoice = socket.assigns.invoice

    case Ksef.submit_sales_invoice(invoice.id) do
      {:ok, _job} ->
        Ksef.subscribe_ksef_status(socket.assigns.current_user.organization_id)

        {:noreply,
         socket
         |> assign(:submission_info, %{socket.assigns.submission_info | status: :submitting})
         |> put_flash(:info, "Wysyłka do KSeF rozpoczęta")}

      {:error, reason} ->
        Logger.error("Failed to submit invoice to KSeF from summary: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Nie udało się wysłać faktury do KSeF")}
    end
  end

  @impl true
  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: status}}, socket) do
    # Only handle if this is the invoice we're viewing
    if socket.assigns.invoice.id == invoice_id do
      # Refetch invoice from DB to get latest state (including ksef_number)
      # TODO: replace authorize?: false + actor: %{} with system actor once available
      invoice = AshSalesInvoice.by_id!(invoice_id, authorize?: false, actor: %{})

      # Convert PubSub status to SubmissionInfo status
      submission_info = Ksef.get_submission_info(invoice)

      {previous_invoices, invoice} = get_previous_invoices(invoice)

      socket =
        socket
        |> assign(:submission_info, submission_info)
        |> assign(:invoice, invoice)
        |> assign(:previous_invoices, previous_invoices)

      # Trigger paper plane animation when submitted successfully
      socket =
        if status == :submitted do
          push_event(socket, "paper-plane-fly", %{})
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp get_previous_invoices(%SalesInvoice{ksef_invoice_kind: :kor} = invoice) do
    original_invoice = SalesInvoices.populate_reference_invoices(invoice.corrected_invoice)

    previous_invoices =
      original_invoice.corrections
      |> Enum.filter(&DateTime.before?(&1.locked_at || &1.inserted_at, invoice.locked_at || invoice.inserted_at))
      |> List.insert_at(0, original_invoice)
      |> Enum.reverse()

    invoice =
      case Enum.find(original_invoice.corrections, &(&1.id == invoice.id)) do
        nil ->
          raise "Correction invoice not found"

        # preserve preloaded fields
        found_invoice ->
          %{
            invoice
            | reference_invoice: found_invoice.reference_invoice,
              corrected_invoice: found_invoice.corrected_invoice
          }
      end

    {previous_invoices, invoice}
  end

  defp get_previous_invoices(%SalesInvoice{ksef_invoice_kind: :vat} = invoice), do: {[], invoice}
end
