defmodule FirmowidWeb.SalesInvoicesLive.Summary do
  @moduledoc """
  LiveView for displaying the summary page after a sales invoice has been created.

  This page shows the invoice details and KSeF submission status, allowing users to:
  - View the created invoice
  - Monitor KSeF submission progress
  - Navigate to edit the invoice or create a new one
  """
  use FirmowidWeb, :live_view

  alias Firmowid.Ksef
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user

    invoice =
      id
      |> SalesInvoices.get_sales_invoice!()
      |> Repo.preload([:sales_invoice_items, corrected_invoice: :sales_invoice_items])

    Bodyguard.permit!(SalesInvoices, :show, current_user, invoice)

    submission_info = Ksef.get_submission_info(invoice)

    # Subscribe to KSeF status updates if submission is in progress
    if submission_info.status == :submitting do
      Ksef.subscribe_ksef_status(current_user.organization_id)
    end

    currency_rate = SalesInvoices.get_currency_rate(invoice)

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
    <div class="max-w-6xl w-full mx-auto my-4 flex flex-col gap-4">
      <p class="text-sm text-grey-500">
        Kreator faktur | <span class="text-grey-700">Faktura wystawiona</span>
      </p>
      <%= case @submission_info.status do %>
        <% :submitting -> %>
          <h1 class="text-[27px]/tight font-medium flex items-baseline gap-1">
            Faktura w trakcie wysyłania
            <span class="inline-flex gap-1">
              <span class="w-1.5 h-1.5 bg-grey-400 rounded-full animate-bounce [animation-delay:-0.3s]">
              </span>
              <span class="w-1.5 h-1.5 bg-grey-400 rounded-full animate-bounce [animation-delay:-0.15s]">
              </span>
              <span class="w-1.5 h-1.5 bg-grey-400 rounded-full animate-bounce"></span>
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
            class="text-sm text-grey-600 hover:text-grey-900"
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
        <div class="text-center flex flex-col justify-center items-center gap-4 bg-redBg text-redText p-8 rounded-md">
          <Lucideicons.triangle_alert class="w-10 h-10 text-red-600" />
          <h2 class="text-xl">Wysyłka do KSeF nie powiodła się.</h2>
          <p :if={@submission_info.error} class="text-sm max-w-lg">
            {@submission_info.error}
          </p>
          <p class="text-sm text-grey-600 mt-2">
            Edytuj fakturę, aby ponowić wysyłkę.
          </p>
          <.link
            navigate={~p"/sprzedazowe/#{@invoice.id}"}
            class={[
              "flex items-center gap-2 px-4 py-2 rounded-md mt-4",
              "bg-turquoise text-white hover:bg-turquoise/90 transition-colors"
            ]}
          >
            <Lucideicons.pencil class="w-4 h-4" /> Przejdź do faktury
          </.link>
        </div>
      <% end %>

      <div class="h-8 invisible" />

      <div class="grid grid-cols-[1fr_650px_1fr] gap-8 justify-center items-start">
        <% list_width = 224 %>
        <% template_width = 595 %>
        <% template_height = 842 %>
        <% scale = list_width / template_width %>

        <div class="space-y-6" style={"width: #{list_width}px;"}>
          <div
            :for={previous_invoice <- @previous_invoices}
            class="space-y-2"
          >
            <p class="text-sm/tight text-grey-700 pl-1">
              {previous_invoice.invoice_number}
            </p>
            <div
              class="border border-grey-200 rounded-lg bg-white shadow-sm overflow-hidden"
              style={"width: #{template_width * scale}px; height: #{template_height * scale}px;"}
            >
              <div class="origin-top-left" style={"transform: scale(#{scale})"}>
                <FirmowidWeb.PdfHTML.sales_invoice
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
          <div class="absolute inset-0 flex items-center justify-center z-0">
            <div class="text-center">
              <Lucideicons.circle_check class="w-24 h-24 text-greenText mx-auto" />
              <p class="mt-4 text-xl font-medium text-grey-700">Wysłano do KSeF!</p>
            </div>
          </div>

          <%!-- Invoice preview - above success (z-10) --%>
          <div
            id="invoice-preview"
            phx-hook="PaperPlane"
            class="relative z-10"
          >
            <div class="max-w-[650px] w-full border border-grey-200 rounded-lg bg-white shadow-sm overflow-hidden">
              <FirmowidWeb.PdfHTML.sales_invoice
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
      invoice =
        invoice_id
        |> SalesInvoices.get_sales_invoice!()
        |> Repo.preload([:sales_invoice_items, corrected_invoice: :sales_invoice_items])

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
