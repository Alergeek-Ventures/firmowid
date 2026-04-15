defmodule FirmowidWeb.Invoicing.Components.SalesInvoiceDetails do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.SubmissionInfo
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Components.InvoiceDownloadModal
  alias FirmowidWeb.Invoicing.Components.InvoiceTimeline

  require Logger

  @impl true
  def mount(socket) do
    {:ok, assign(socket, chat: false, show_timeline: false, is_cost_invoice: false)}
  end

  @impl true
  def update(assigns, socket) do
    alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections
    # Fetch submission info when invoice is assigned
    submission_info =
      if assigns[:invoice] do
        Ksef.get_submission_info(assigns.invoice)
      else
        %SubmissionInfo{status: :not_submitted}
      end

    # Use already-loaded corrections and annotate directly
    # (Ash.load! with :annotated_corrections re-fetches, losing attribute selection)
    invoice =
      assigns.invoice
      |> Ash.load!(
        [
          :net_value,
          :vat_value,
          :gross_value,
          :internal_note,
          sales_invoice_items: [:net_value, :vat_value, :gross_value],
          corrections: [
            :net_value,
            :vat_value,
            :gross_value,
            :internal_note,
            sales_invoice_items: [:net_value, :vat_value, :gross_value]
          ]
        ],
        scope: assigns.scope
      )
      |> then(fn inv -> %{inv | corrections: AnnotatedCorrections.annotate(inv)} end)

    latest_invoice_snapshot =
      assigns.invoice
      |> Ash.load!(
        [
          :effective_snapshot,
          :gross_value,
          :currency,
          latest_correction: [
            :net_value,
            :vat_value,
            :gross_value,
            :currency,
            :sale_date,
            :due_date,
            :buyer_display_name_label,
            sales_invoice_items: [:net_value, :vat_value, :gross_value]
          ]
        ],
        scope: assigns.scope
      )
      |> Map.get(:effective_snapshot)
      |> Ash.load!(
        [
          :net_value,
          :vat_value,
          :gross_value,
          :currency,
          :buyer_display_name_label,
          sales_invoice_items: [:net_value, :vat_value, :gross_value]
        ],
        scope: assigns.scope
      )

    cancelled? = Decimal.eq?(latest_invoice_snapshot.gross_value, 0)

    description =
      latest_invoice_snapshot.sales_invoice_items
      |> List.first(%{})
      |> Map.get(:name, "")

    internal_notes =
      [invoice | invoice.corrections]
      |> Enum.map(& &1.internal_note)
      |> Enum.reject(&is_nil/1)

    socket =
      socket
      |> assign(assigns)
      |> assign(
        invoice: invoice,
        submission_info: submission_info,
        party_display_name: latest_invoice_snapshot.buyer_display_name_label,
        description: description,
        latest_invoice_snapshot: latest_invoice_snapshot,
        invoices_for_preview: Enum.reverse([invoice | invoice.corrections]),
        internal_notes: internal_notes,
        cancelled?: cancelled?,
        show_timeline_button: show_timeline_button?(submission_info)
      )

    {:ok, socket}
  end

  attr :invoice, SalesInvoice, required: true
  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true
  attr :potential_transactions, :list, default: []
  attr :show_vat_for_sales_invoice, :boolean, default: true
  attr :current_user, :map, required: true
  attr :return_to, :string, default: nil
  attr :ksef_connected?, :boolean, default: false
  attr :scope, :map, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div id="invoice-show" class="flex flex-col">
      <InvoiceDetails.invoice_header
        is_cost_invoice={false}
        issue_date={@invoice.issue_date}
        party_display_name={@party_display_name}
        description={@description}
        return_to={@return_to}
      />

      <div class="flex min-w-0 flex-col bg-white lg:flex-row">
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
                    if @invoice.ksef_number,
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
                  :if={@invoice.is_deletable}
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
                  :if={!!@invoice.ksef_number and not @cancelled?}
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
                <.live_component
                  module={InvoiceDownloadModal}
                  id={"sales-download-#{@invoice.id}"}
                  download_path={~p"/sprzedazowe/#{@invoice.id}/pobierz"}
                  button_class={button_styles(%{color: "light_grey", size: "small", new: true})}
                  button_label="Pobierz"
                />
              </div>

              <.button
                :if={@show_timeline_button}
                class={[
                  "ml-auto",
                  SubmissionInfo.failed?(@submission_info) &&
                    "hover:bg-redText hover:ring-redText hover:text-redBg text-redText"
                ]}
                color="light_grey"
                size="small"
                new={true}
                phx-click="show_timeline"
                phx-target={@myself}
              >
                Historia faktury
                <span
                  :if={SubmissionInfo.failed?(@submission_info)}
                  class="bg-redText border-redBg text-redBg absolute -top-2.5 -right-2.5 flex size-5 items-center justify-center rounded-full border-2 p-1 text-xs font-bold"
                >
                  !
                </span>
              </.button>

              <.button
                :if={
                  @ksef_connected? and not is_nil(@invoice.invoice_number) and
                    (SubmissionInfo.not_submitted?(@submission_info) or
                       SubmissionInfo.submitting?(@submission_info))
                }
                id="send-to-ksef-button"
                disabled={SubmissionInfo.submitting?(@submission_info)}
                phx-hook="Tippy"
                data-tippy-content={
                  if SubmissionInfo.submitting?(@submission_info),
                    do: "Wysyłanie...",
                    else: "Wyślij do KSeF"
                }
                data-tippy-delay="100"
                color="turquoise"
                size="small"
                new={true}
                class={[SubmissionInfo.submitting?(@submission_info) && "cursor-wait"]}
                phx-click="send_to_ksef"
                phx-target={@myself}
              >
                Wyślij
                <%= if SubmissionInfo.submitting?(@submission_info) do %>
                  <.icon name="hero-arrow-path" class="size-5 animate-spin" />
                <% else %>
                  <Lucideicons.send class="size-5" />
                <% end %>
              </.button>

              <div :if={@invoice.is_deletable} class="absolute">
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
                :if={@invoice.invoice_number}
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
                value={@latest_invoice_snapshot.buyer_display_name_label}
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
                  @latest_invoice_snapshot.gross_value
                )
              }
            />
          <% end %>

          <%= if @internal_notes != [] do %>
            <InvoiceDetails.invoice_notes internal_notes={@internal_notes} />
          <% end %>

          <InvoiceDetails.invoice_preview>
            <:subpreview
              :for={invoice <- @invoices_for_preview}
              invoice_number_label={invoice.invoice_number}
            >
              <.link href={~p"/sprzedazowe/#{invoice.id}/pobierz"} download>
                <InvoiceDetails.scalable_invoice_preview
                  id={"preview-#{invoice.id}"}
                  class="max-w-full min-w-0"
                >
                  <FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf.sales_invoice
                    sales_invoice={invoice}
                    logo_url={assigns[:logo_url]}
                    currency_rate={Invoicing.get_currency_rate(invoice)}
                    show_vat={@show_vat_for_sales_invoice}
                    reference_invoice={invoice.reference_invoice}
                  />
                </InvoiceDetails.scalable_invoice_preview>
              </.link>
            </:subpreview>
          </InvoiceDetails.invoice_preview>
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
                module={FirmowidWeb.Invoicing.SalesInvoices.Components.Assistant}
                id="invoice-assistant"
                invoice={@invoice}
                current_user={@current_user}
                scope={@scope}
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

    case Ksef.submit_sales_invoice(invoice.id, socket.assigns.scope) do
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

  defp show_timeline_button?(submission_info), do: SubmissionInfo.attempted?(submission_info)
end
