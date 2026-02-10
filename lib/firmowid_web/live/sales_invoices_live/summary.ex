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

    socket =
      socket
      |> assign(:invoice, invoice)
      |> assign(:reference_invoice, get_reference_invoice(invoice))
      |> assign(:submission_info, submission_info)
      |> assign(:currency_rate, currency_rate)

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
        <div class="flex items-center gap-6">
          <.link
            navigate={~p"/sprzedazowe/#{@invoice.id}"}
            class="flex items-center gap-2 text-gray-600"
          >
            <Lucideicons.pencil class="size-4" /> Edytuj
          </.link>
          <.link
            href={~p"/sprzedazowe/#{@invoice.id}/pobierz"}
            class="flex items-center gap-2 text-gray-600"
          >
            <Lucideicons.download class="size-4" /> Pobierz
          </.link>
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

      <div class="flex justify-center">
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
                reference_invoice={@reference_invoice}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
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

      socket =
        socket
        |> assign(:submission_info, submission_info)
        |> assign(:invoice, invoice)
        |> assign(:reference_invoice, get_reference_invoice(invoice))

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

  defp get_reference_invoice(%SalesInvoices.SalesInvoice{ksef_invoice_kind: :kor} = invoice) do
    SalesInvoices.get_reference_invoice_for_correction(invoice)
  end

  defp get_reference_invoice(_invoice), do: nil
end
