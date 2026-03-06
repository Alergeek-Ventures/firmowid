defmodule FirmowidWeb.Components.Invoicing.SalesInvoiceDetails do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.Ksef
  alias Firmowid.Ksef.SubmissionInfo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice
  alias FirmowidWeb.Components.Invoicing.InvoiceDetails, as: InvoiceDetails
  alias FirmowidWeb.Components.Invoicing.InvoiceTimeline

  require Logger

  defp get_invoices_for_preview(%SalesInvoice{ksef_invoice_kind: :vat} = invoice) do
    corrections = Enum.map(invoice.corrections, &%{&1 | corrected_invoice: invoice})

    invoices = [invoice | corrections]
    reference_invoices = [nil | invoices]

    [invoices, reference_invoices] |> Enum.zip() |> Enum.reverse()
  end

  attr :invoice, SalesInvoice, required: true
  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true
  attr :potential_transactions, :list, default: []
  attr :show_vat_for_sales_invoice, :boolean, default: true
  attr :current_user, :map, required: true
  attr :return_to, :string, default: nil
  attr :ksef_connected?, :boolean, default: false
  attr :reference_invoice, :map, default: nil

  @impl true
  def render(assigns) do
    invoice_to_copy = SalesInvoices.get_latest_invoice_snapshot(assigns.invoice)
    invoices_for_preview = get_invoices_for_preview(assigns.invoice)
    cancelled? = latest_invoice_snapshot |> SalesInvoice.get_gross_value() |> Decimal.eq?(0)

    assigns =
      assigns
      |> assign(:is_cost_invoice, false)
      |> assign(
        :party_display_name,
        SalesInvoices.buyer_display_name(latest_invoice_snapshot)
      )
      |> assign(
        :description,
        case latest_invoice_snapshot.sales_invoice_items do
          [first | _] -> Map.get(first, :name, "")
          _ -> ""
        end
      )
      |> assign(:show_timeline_button, show_timeline_button?(assigns.submission_info))
      |> assign(:latest_invoice_snapshot, latest_invoice_snapshot)
      |> assign(:invoices_for_preview, invoices_for_preview)
      |> assign(:cancelled?, cancelled?)

    ~H"""
    <div id="invoice-show" class="flex flex-col">
      <InvoiceDetails.invoice_header
        is_cost_invoice={false}
        issue_date={@invoice.issue_date}
        party_display_name={@party_display_name}
        description={@description}
        return_to={@return_to}
      />

      <div class="flex flex-col lg:flex-row min-w-0 bg-white">
        <InvoiceDetails.aside>
          <%= if @show_timeline do %>
            <InvoiceTimeline.invoice_timeline
              invoice={@invoice}
              invoice_type={:sales}
              submission_info={@submission_info}
            />
          <% else %>
            <div class="flex flex-row justify-between gap-4">
              <div class="flex flex-row gap-3 xl:gap-4">
                <.link
                  class={button_styles(%{color: "light_grey", size: "small", new: true})}
                  navigate={~p"/sprzedazowe?skopiuj=#{@latest_invoice_snapshot.id}"}
                >
                  <Lucideicons.copy /><span class="hidden xl:inline">Kopiuj</span>
                </.link>

                <.link
                  id="edit-invoice-link"
                  phx-hook="Tippy"
                  data-tippy-content={
                    if SalesInvoice.ksef_submitted?(@invoice),
                      do: "Wystaw fakturę korygującą",
                      else: "Edytuj fakturę"
                  }
                  data-tippy-delay="100"
                  class={button_styles(%{color: "light_grey", size: "small", new: true})}
                  navigate={~p"/sprzedazowe/#{@latest_invoice_snapshot.id}/edytuj"}
                >
                  <.icon name="hero-pencil-square" class="size-4" />
                  <span class="hidden xl:inline">
                    Edytuj
                  </span>
                </.link>

                <.button
                  :if={SalesInvoice.deletable?(@invoice)}
                  phx-click={show_modal("delete-invoice-modal")}
                  color="light_grey"
                  size="small"
                  new={true}
                >
                  <.icon name="hero-trash-solid" class="size-4" />
                  <span class="hidden xl:inline">
                    Usuń
                  </span>
                </.button>

                <.button
                  :if={SalesInvoice.ksef_submitted?(@invoice) and not @cancelled?}
                  phx-click={show_modal("cancel-invoice-modal")}
                  color="light_grey"
                  size="small"
                  new={true}
                >
                  <.icon name="hero-trash-solid" class="size-4" />
                  <span class="hidden xl:inline">
                    Anuluj
                  </span>
                </.button>

                <%!-- should download button download invoice with corrections? --%>
                <.link
                  class={button_styles(%{color: "light_grey", size: "small", new: true})}
                  href={~p"/sprzedazowe/#{@invoice.id}/pobierz"}
                  download
                >
                  <Lucideicons.download /><span class="hidden xl:inline">Pobierz</span>
                </.link>
              </div>

              <.button
                :if={@show_timeline_button}
                class={[
                  "ml-auto",
                  @submission_info.status == :failed &&
                    "hover:ring-redText text-redText hover:text-redBg hover:bg-redText"
                ]}
                color="light_grey"
                size="small"
                new={true}
                phx-click="show_timeline"
                phx-target={@myself}
              >
                Historia faktury
                <span
                  :if={@submission_info.status == :failed}
                  class={[
                    "absolute -top-2.5 -right-2.5 bg-redText text-redBg text-xs w-5 h-5",
                    "rounded-full flex items-center justify-center font-bold
                    border-redBg border-2 p-1"
                  ]}
                >
                  !
                </span>
              </.button>

              <.button
                :if={
                  @ksef_connected? and SalesInvoice.confirmed?(@invoice) and
                    @submission_info.status in [:not_submitted, :submitting]
                }
                id="send-to-ksef-button"
                disabled={@submission_info.status == :submitting}
                phx-hook="Tippy"
                data-tippy-content={
                  if @submission_info.status == :submitting,
                    do: "Wysyłanie...",
                    else: "Wyślij do KSeF"
                }
                data-tippy-delay="100"
                color="turquoise"
                size="small"
                new={true}
                class={@submission_info.status == :submitting && "cursor-wait"}
                phx-click="send_to_ksef"
                phx-target={@myself}
              >
                Wyślij
                <%= if @submission_info.status == :submitting do %>
                  <.icon name="hero-arrow-path" class="size-5 animate-spin" />
                <% else %>
                  <Lucideicons.send class="size-5" />
                <% end %>
              </.button>

              <div :if={SalesInvoice.deletable?(@invoice)} class="absolute">
                <.modal id="delete-invoice-modal" on_cancel={hide_modal("delete-invoice-modal")}>
                  <p>
                    Czy na pewno chcesz usunąć fakturę <span class="font-semibold">{@invoice.invoice_number}</span>?
                  </p>
                  <div class="mt-6 flex justify-end gap-3">
                    <.button
                      variant="outline"
                      color="black"
                      phx-click={hide_modal("delete-invoice-modal")}
                    >
                      Anuluj
                    </.button>
                    <.button
                      color="red"
                      phx-click={
                        JS.exec("data-cancel", to: "#delete-invoice-modal")
                        |> JS.push("delete")
                      }
                      phx-disable-with="Usuwanie..."
                    >
                      Usun
                    </.button>
                  </div>
                </.modal>
              </div>

              <div class="absolute">
                <.modal id="cancel-invoice-modal" on_cancel={hide_modal("cancel-invoice-modal")}>
                  <p>
                    Czy na pewno chcesz anulować fakturę <span class="font-semibold">{@invoice.invoice_number}</span>?
                    Wystawimy fakturę korygującą zerującą pozycje.
                  </p>
                  <div class="mt-6 flex justify-end gap-3">
                    <.button
                      variant="outline"
                      color="black"
                      phx-click={hide_modal("cancel-invoice-modal")}
                    >
                      Wróć
                    </.button>
                    <.button
                      color="orange"
                      phx-click={
                        JS.exec("data-cancel", to: "#cancel-invoice-modal")
                        |> JS.push("cancel")
                      }
                      phx-disable-with="Anulowanie..."
                    >
                      Anuluj fakturę
                    </.button>
                  </div>
                </.modal>
              </div>

              <span
                :if={SalesInvoice.confirmed?(@invoice)}
                id="share-invoice-button-container"
                phx-hook="Tippy"
                data-tippy-content="Skopiuj link do faktury"
                data-tippy-delay="100"
              >
                <.button
                  id="share-invoice-button"
                  phx-hook="CopyToClipboard"
                  color={if @invoice.share_token, do: "turquoise", else: "light_grey"}
                  size="small"
                  new={true}
                  phx-click="create_share_link"
                >
                  <Lucideicons.share_2 />
                </.button>
              </span>
            </div>

            <InvoiceDetails.invoice_metadata>
              <InvoiceDetails.invoice_metadata_piece
                label="Numer faktury"
                value={@invoice.invoice_number}
                piece_id="inv-id"
              />
              <InvoiceDetails.invoice_metadata_piece
                :if={@invoice.ksef_number != nil}
                label="Identyfikator KSeF"
                value={@invoice.ksef_number}
                piece_id="ksef-id"
              />
              <InvoiceDetails.invoice_metadata_piece
                label="Kupujący"
                value={Firmowid.SalesInvoices.buyer_display_name(@latest_invoice_snapshot)}
                piece_id="buyer"
              />
              <InvoiceDetails.invoice_metadata_piece
                label="Data wystawienia"
                value={@invoice.issue_date}
                piece_id="issue-date"
              />
              <InvoiceDetails.invoice_metadata_piece
                label="Data sprzedaży"
                value={@latest_invoice_snapshot.sale_date}
                piece_id="sale-date"
              />
              <InvoiceDetails.invoice_metadata_piece
                label="Termin płatności"
                value={@latest_invoice_snapshot.due_date}
                piece_id="due-date"
              />
            </InvoiceDetails.invoice_metadata>

            <InvoiceDetails.invoice_amount
              is_cost_invoice={false}
              total_amount={
                Money.new(
                  @latest_invoice_snapshot.currency,
                  Firmowid.SalesInvoices.SalesInvoice.get_gross_value(@latest_invoice_snapshot)
                )
              }
            />
          <% end %>

          <%= case @invoices_for_preview do %>
            <% [{invoice, nil}] -> %>
              <InvoiceDetails.invoice_preview>
                <.link href={~p"/sprzedazowe/#{@invoice.id}/pobierz"} download>
                  <InvoiceDetails.invoice_preview_border>
                    <InvoiceDetails.scalable_invoice_preview>
                      <FirmowidWeb.PdfHTML.sales_invoice
                        sales_invoice={invoice}
                        currency_rate={Firmowid.SalesInvoices.get_currency_rate(invoice)}
                        show_vat={@show_vat_for_sales_invoice}
                        reference_invoice={%{}}
                      />
                    </InvoiceDetails.scalable_invoice_preview>
                  </InvoiceDetails.invoice_preview_border>
                </.link>
              </InvoiceDetails.invoice_preview>
            <% [latest_invoice | previous_invoices] -> %>
              <InvoiceDetails.invoice_preview>
                <div class="flex flex-col-reverse xl:flex-row gap-4 w-full">
                  <div class="flex flex-col gap-4 w-full min-w-0 shrink-2">
                    <InvoiceDetails.invoice_subpreview
                      :for={{invoice, refrence_invoice} <- previous_invoices}
                      label={invoice.invoice_number}
                    >
                      <InvoiceDetails.scalable_invoice_preview
                        id={"preview-#{invoice.id}"}
                        class="max-w-full min-w-0"
                      >
                        <FirmowidWeb.PdfHTML.sales_invoice
                          sales_invoice={invoice}
                          currency_rate={Firmowid.SalesInvoices.get_currency_rate(invoice)}
                          show_vat={@show_vat_for_sales_invoice}
                          reference_invoice={refrence_invoice}
                        />
                      </InvoiceDetails.scalable_invoice_preview>
                    </InvoiceDetails.invoice_subpreview>
                  </div>

                  <% {latest_invoice, latest_invoice_reference} = latest_invoice %>
                  <InvoiceDetails.invoice_subpreview label={latest_invoice.invoice_number}>
                    <.link href={~p"/sprzedazowe/#{latest_invoice.id}/pobierz"} download>
                      <InvoiceDetails.scalable_invoice_preview
                        id={"preview-#{latest_invoice.id}"}
                        class="w-full max-w-full min-w-0"
                      >
                        <FirmowidWeb.PdfHTML.sales_invoice
                          sales_invoice={latest_invoice}
                          currency_rate={Firmowid.SalesInvoices.get_currency_rate(latest_invoice)}
                          show_vat={@show_vat_for_sales_invoice}
                          reference_invoice={latest_invoice_reference}
                        />
                      </InvoiceDetails.scalable_invoice_preview>
                    </.link>
                  </InvoiceDetails.invoice_subpreview>
                </div>
              </InvoiceDetails.invoice_preview>
          <% end %>
        </InvoiceDetails.aside>

        <InvoiceDetails.main>
          <%= cond do %>
            <% @invoice.skip_invoicing -> %>
              <InvoiceDetails.invoice_skipped_view is_cost_invoice={false} />
            <% not Enum.empty?(@invoice.transactions) -> %>
              <InvoiceDetails.transaction_match
                is_cost_invoice={false}
                transactions={@invoice.transactions}
              />
            <% @chat -> %>
              <.live_component
                module={FirmowidWeb.SalesInvoicesLive.Assistant}
                id="invoice-assistant"
                invoice={@invoice}
                current_user={@current_user}
              />
            <% true -> %>
              <InvoiceDetails.potential_transactions
                potential_transactions={@potential_transactions}
                is_cost_invoice={@is_cost_invoice}
                invoice={@invoice}
              />
          <% end %>
        </InvoiceDetails.main>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, chat: false, show_timeline: false)}
  end

  @impl true
  def update(assigns, socket) do
    # Fetch submission info when invoice is assigned
    submission_info =
      if assigns[:invoice] do
        Ksef.get_submission_info(assigns.invoice)
      else
        %SubmissionInfo{status: :not_submitted}
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:submission_info, submission_info)

    {:ok, socket}
  end

  @impl true
  def handle_event("show_chat", _params, socket) do
    {:noreply, assign(socket, chat: true)}
  end

  def handle_event("close_chat", _params, socket) do
    {:noreply, assign(socket, chat: false)}
  end

  def handle_event("show_timeline", _params, socket) do
    {:noreply, assign(socket, show_timeline: true)}
  end

  def handle_event("hide_timeline", _params, socket) do
    {:noreply, assign(socket, show_timeline: false)}
  end

  def handle_event("send_to_ksef", _params, socket) do
    invoice = socket.assigns.invoice

    case Ksef.submit_sales_invoice(invoice.id) do
      {:ok, _job} ->
        Ksef.subscribe_ksef_status(socket.assigns.current_user.organization_id)

        {:noreply,
         socket
         |> assign(:submission_info, %SubmissionInfo{status: :submitting})
         |> put_flash(:info, "Wysyłka do KSeF rozpoczęta")}

      {:error, reason} ->
        Logger.error("Failed to submit to KSeF: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, ksef_error_message(reason))}
    end
  end

  defp ksef_error_message(:not_authenticated), do: "Organizacja nie jest połączona z KSeF"
  defp ksef_error_message(:invoice_is_draft), do: "Nie można wysłać szkicu faktury"
  defp ksef_error_message(:invoice_already_locked), do: "Faktura została już wysłana do KSeF"

  defp ksef_error_message({:invalid_for_ksef, _}), do: "Faktura zawiera błędy uniemożliwiające wysyłkę do KSeF"

  defp ksef_error_message(_), do: "Nie udało się wysłać faktury do KSeF"

  defp show_timeline_button?(%SubmissionInfo{status: :not_submitted}), do: false
  defp show_timeline_button?(_submission_info), do: true
end
