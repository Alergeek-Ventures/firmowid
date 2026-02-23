defmodule FirmowidWeb.Components.Invoicing.SalesInvoiceDetails do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.Ksef
  alias Firmowid.Ksef.SubmissionInfo
  alias Firmowid.SalesInvoices.SalesInvoice
  alias FirmowidWeb.Components.Invoicing.InvoiceDetails, as: InvoiceDetails
  alias FirmowidWeb.Components.Invoicing.InvoiceTimeline

  require Logger

  def cancelable?(%SalesInvoice{} = invoice) do
    if Decimal.eq?(SalesInvoice.get_gross_value(invoice), 0) do
      false
    else
      SalesInvoice.editable?(invoice)
    end
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
    assigns =
      assigns
      |> assign(:is_cost_invoice, false)
      |> assign(
        :party_display_name,
        Firmowid.SalesInvoices.buyer_display_name(assigns.invoice)
      )
      |> assign(
        :description,
        case assigns.invoice.sales_invoice_items do
          [first | _] -> Map.get(first, :name, "")
          _ -> ""
        end
      )
      |> assign(
        :show_timeline_button,
        show_timeline_button?(assigns.submission_info)
      )

    ~H"""
    <div id="invoice-show" class="flex flex-col">
      <InvoiceDetails.invoice_header
        is_cost_invoice={false}
        issue_date={@invoice.issue_date}
        party_display_name={@party_display_name}
        description={@description}
        return_to={@return_to}
      />

      <div class="flex flex-col justify-between px-8 gap-4 lg:gap-12 lg:flex-row min-w-0">
        <aside class={[
          "w-full lg:max-w-[400px] xl:max-w-[650px] shrink-0 grow",
          "flex flex-col gap-4 order-last lg:order-0 py-8 pr-8",
          "max-h-[calc(100vh-var(--navbar-height)-128px)] overflow-y-auto",
          "lg:h-[calc(100vh-var(--navbar-height)-128px)]"
        ]}>
          <%= if @show_timeline do %>
            <InvoiceTimeline.invoice_timeline
              invoice={@invoice}
              invoice_type={:sales}
              submission_info={@submission_info}
            />
          <% else %>
            <div class="flex flex-row justify-end gap-2">
              <button
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
                class={[
                  "transition-all transition-duration-300",
                  "px-2 py-1 flex items-center justify-center rounded",
                  @submission_info.status == :submitting && "bg-turquoise-500 text-white cursor-wait",
                  @submission_info.status != :submitting &&
                    "bg-turquoise-600 text-white hover:bg-turquoise-800"
                ]}
                phx-click="send_to_ksef"
                phx-target={@myself}
              >
                <.icon
                  name={
                    if @submission_info.status == :submitting,
                      do: "hero-arrow-path",
                      else: "hero-paper-airplane"
                  }
                  class={
                    if @submission_info.status == :submitting,
                      do: "w-5 h-5 animate-spin",
                      else: "w-5 h-5"
                  }
                />
              </button>
              <.link
                :if={SalesInvoice.editable?(@invoice)}
                id="edit-invoice-link"
                phx-hook="Tippy"
                data-tippy-content="Wystaw fakturę korygującą"
                data-tippy-delay="100"
                class={[
                  "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
                  "px-2 py-1 flex items-center justify-center rounded"
                ]}
                navigate={~p"/sprzedazowe/#{@invoice.id}/edytuj"}
              >
                <.icon name="hero-pencil-square-solid" class="w-5 h-5" />
              </.link>

              <button
                :if={cancelable?(@invoice) and not SalesInvoice.deletable?(@invoice)}
                id="cancel-invoice-button"
                phx-hook="Tippy"
                data-tippy-content="Anuluj fakturę (korekta)"
                data-tippy-delay="100"
                class={[
                  "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
                  "px-2 py-1 flex items-center justify-center rounded"
                ]}
                phx-click={show_modal("cancel-invoice-modal")}
              >
                <.icon name="hero-no-symbol" class="w-5 h-5" />
              </button>
              <button
                :if={SalesInvoice.deletable?(@invoice)}
                id="delete-invoice-button"
                phx-hook="Tippy"
                data-tippy-content="Usuń fakturę"
                data-tippy-delay="100"
                class={[
                  "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
                  "px-2 py-1 flex items-center justify-center rounded"
                ]}
                phx-click={show_modal("delete-invoice-modal")}
              >
                <.icon name="hero-trash-solid" class="w-5 h-5" />
              </button>
              <button
                :if={@show_timeline_button}
                id="timeline-button"
                phx-hook="Tippy"
                data-tippy-content="Historia dokumentu"
                data-tippy-delay="100"
                class={[
                  "relative",
                  "hover:text-white hover:bg-darkGrey text-darkGrey transition-all transition-duration-300",
                  "px-2 py-1 flex items-center justify-center rounded",
                  @submission_info.status == :failed &&
                    "hover:ring-redText text-redText hover:text-redBg hover:bg-redText"
                ]}
                phx-click="show_timeline"
                phx-target={@myself}
              >
                <.icon name="hero-clock" class="w-5 h-5" />
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
              </button>

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

              <div :if={cancelable?(@invoice)} class="absolute">
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
                <button
                  id="share-invoice-button"
                  phx-hook="CopyToClipboard"
                  class={[
                    "transition-all transition-duration-300",
                    "px-2 py-1 flex items-center justify-center rounded",
                    if(@invoice.share_token,
                      do: "bg-turquoise-600 text-white hover:bg-turquoise-800",
                      else: "hover:text-white hover:bg-darkGrey text-darkGrey"
                    )
                  ]}
                  phx-click="create_share_link"
                >
                  <.icon name="hero-share" class="w-5 h-5" />
                </button>
              </span>
            </div>

            <div class="py-4">
              <InvoiceDetails.sales_invoice_metadata invoice={@invoice} />
            </div>
          <% end %>

          <h3 class="self-start text-sm uppercase text-darkGrey mt-8">Podgląd faktury</h3>
          <div class="mb-8 mt-4 transition-opacity transition-duration-300 hover:opacity-50">
            <%= if @preview_type == :html do %>
              <div class="w-full h-full max-h-[80vh] border-black border-2 rounded-lg overflow-hidden">
                <a href={~p"/sprzedazowe/#{@invoice.id}/pobierz"} target="_blank">
                  <FirmowidWeb.PdfHTML.sales_invoice
                    sales_invoice={@invoice}
                    currency_rate={Firmowid.SalesInvoices.get_currency_rate(@invoice)}
                    show_vat={@show_vat_for_sales_invoice}
                    reference_invoice={@reference_invoice}
                  />
                </a>
              </div>
            <% end %>
          </div>
        </aside>

        <main class="grow py-8 lg:pl-8 border-b lg:border-b-0 lg:border-l border-darkGrey/[.3] h-[calc(100vh-var(--navbar-height)-128px)]">
          <%= cond do %>
            <% @invoice.skip_invoicing -> %>
              <InvoiceDetails.invoice_skipped_view />
            <% length(@invoice.transactions) == 1 -> %>
              <InvoiceDetails.single_transaction_match
                is_cost_invoice={false}
                transaction={@invoice.transactions |> hd()}
              />
            <% length(@invoice.transactions) > 1 -> %>
              <InvoiceDetails.multiple_transactions_match
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
            <% @potential_transactions == [] -> %>
              <div class="flex flex-col gap-6 items-center mb-10">
                <div class="gap-4 flex flex-col items-center p-4 rounded-md text-center">
                  <.icon name="hero-face-frown" class="w-10 h-10 block" />
                  <h3 class="text-lg font-semibold">Brak rekomendacji</h3>
                  <p class="max-w-[400px]">
                    Firmowid nie znalazl zadnych transakcji, ktore potencjalnie pasowałyby do tej faktury.
                  </p>
                  <.button
                    phx-click="show_chat"
                    phx-target={@myself}
                    color="orange"
                    class="w-full mt-2"
                  >
                    Popros Firmowida o pomoc
                  </.button>
                </div>
              </div>
              <hr class="w-full text-grey-200" />
              <h3 class="text-md font-semibold my-10">Co jeszcze mozesz zrobic?</h3>
              <InvoiceDetails.skip_invoicing show_bank_transfer_modal={false} invoice={@invoice} />
            <% true -> %>
              <div class="flex flex-col gap-16">
                <InvoiceDetails.potential_transactions_list
                  potential_transactions={@potential_transactions}
                  name_field={:debtor_name}
                />
                <InvoiceDetails.skip_invoicing show_bank_transfer_modal={false} invoice={@invoice} />
              </div>
          <% end %>
        </main>
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
