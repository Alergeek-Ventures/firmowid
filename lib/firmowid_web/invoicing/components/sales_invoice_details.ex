defmodule FirmowidWeb.Invoicing.Components.SalesInvoiceDetails do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.SubmissionInfo
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Components.InvoiceDownloadModal
  alias FirmowidWeb.Invoicing.Components.InvoiceTimeline
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @impl true
  def mount(socket) do
    {:ok, assign(socket, show_timeline: false, is_cost_invoice: false)}
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
          :amount,
          :effective_sale_date,
          :effective_due_date,
          :internal_note,
          sales_invoice_items: [:net_value, :vat_value, :gross_value],
          corrections: [
            :net_value,
            :vat_value,
            :gross_value,
            :amount,
            :internal_note,
            :email_deliveries,
            sales_invoice_items: [:net_value, :vat_value, :gross_value]
          ]
        ],
        scope: assigns.scope
      )
      |> then(fn inv -> %{inv | corrections: AnnotatedCorrections.annotate(inv)} end)

    latest_invoice_snapshot =
      assigns.invoice
      |> Ash.load!([:amount, :effective_snapshot], scope: assigns.scope)
      |> Map.get(:effective_snapshot)
      |> Ash.load!(
        [
          :net_value,
          :vat_value,
          :gross_value,
          :amount,
          :sale_date,
          :due_date,
          :buyer_display_name_label,
          sales_invoice_items: [:net_value, :vat_value, :gross_value]
        ],
        scope: assigns.scope
      )

    cancelled? = Decimal.eq?(Money.to_decimal(latest_invoice_snapshot.amount), 0)

    description =
      latest_invoice_snapshot.sales_invoice_items
      |> List.first(%{})
      |> Map.get(:name, "")

    internal_notes =
      invoice.corrections
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
        show_timeline_button: show_timeline_button?(submission_info),
        can_write_invoicing?: Ash.can?({SalesInvoice, :revise}, assigns.current_user)
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
  attr :scope, :map, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div id="invoice-show" class="flex flex-col">
      <InvoiceDetails.invoice_header
        variant={invoice_source_badge_variant(@invoice)}
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
                  :if={@can_write_invoicing?}
                  navigate={
                    Navigation.sales_invoice_creator_path(%{skopiuj: @latest_invoice_snapshot.id})
                  }
                  kind="button"
                  variant="secondary"
                  size="small"
                >
                  <Lucideicons.copy /><span class="hidden xl:inline">Kopiuj</span>
                </.link>

                <%= if @can_write_invoicing? do %>
                  <%= if SubmissionInfo.editing_blocked?(@invoice, @submission_info) or
                          SubmissionInfo.outside_ksef?(@invoice, @submission_info) do %>
                    <span
                      id="edit-invoice-button-tooltip"
                      phx-hook="Tippy"
                      data-tippy-content={
                        SubmissionInfo.edit_unavailable_reason(@invoice, @submission_info)
                      }
                      data-tippy-delay="100"
                      class="inline-flex"
                      tabindex="0"
                    >
                      <.button
                        id="edit-invoice-button"
                        type="button"
                        variant="secondary"
                        size="small"
                        disabled
                        aria-describedby="edit-invoice-button-description"
                      >
                        <.icon name="hero-pencil-square" class="size-4" />
                        <span class="hidden xl:inline">Edytuj</span>
                      </.button>
                    </span>
                    <span id="edit-invoice-button-description" class="sr-only">
                      {SubmissionInfo.edit_unavailable_reason(@invoice, @submission_info)}
                    </span>
                  <% else %>
                    <.link
                      id="edit-invoice-link"
                      phx-hook="Tippy"
                      data-tippy-content={
                        if @invoice.ksef_number,
                          do: "Wystaw fakturę korygującą",
                          else: "Edytuj fakturę"
                      }
                      data-tippy-delay="100"
                      navigate={
                        Navigation.sales_invoice_edit_path(@latest_invoice_snapshot, @return_to)
                      }
                      kind="button"
                      variant="secondary"
                      size="small"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                      <span class="hidden xl:inline">Edytuj</span>
                    </.link>
                  <% end %>
                <% end %>

                <.button
                  :if={@can_write_invoicing? and @invoice.is_deletable}
                  phx-click={show_modal("delete-invoice-modal")}
                  variant="secondary"
                  size="small"
                >
                  <.icon name="hero-trash-solid" class="size-4" />
                  <span class="hidden xl:inline">
                    Usuń
                  </span>
                </.button>

                <.button
                  :if={@can_write_invoicing? and !!@invoice.ksef_number and not @cancelled?}
                  phx-click={show_modal("cancel-invoice-modal")}
                  variant="secondary"
                  size="small"
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
                  download_path={Navigation.sales_invoice_pdf_path(@invoice)}
                  trigger_variant="secondary"
                  trigger_size="small"
                  button_label="Pobierz"
                />
              </div>

              <.button
                :if={@show_timeline_button}
                class={[
                  "ml-auto",
                  SubmissionInfo.failed?(@submission_info) &&
                    "text-brick-700 hover:bg-brick-700 hover:text-brick-200 hover:ring-brick-700"
                ]}
                variant="secondary"
                size="small"
                phx-click="show_timeline"
                phx-target={@myself}
              >
                Historia faktury
                <span
                  :if={SubmissionInfo.failed?(@submission_info)}
                  class="absolute -top-2.5 -right-2.5 flex size-5 items-center justify-center rounded-full border-2 border-brick-200 bg-brick-700 p-1 text-xs font-bold text-brick-200"
                >
                  !
                </span>
              </.button>

              <div :if={@can_write_invoicing? and @invoice.is_deletable} class="absolute">
                <.modal id="delete-invoice-modal" on_cancel={hide_modal("delete-invoice-modal")}>
                  <p>
                    Czy na pewno chcesz usunąć fakturę <span class="font-semibold">{@invoice.invoice_number}</span>?
                  </p>
                  <div class="mt-6 flex justify-end gap-3">
                    <.button
                      type="button"
                      variant="secondary"
                      phx-click={hide_modal("delete-invoice-modal")}
                    >
                      Anuluj
                    </.button>
                    <.button
                      phx-click={
                        JS.exec("data-cancel", to: "#delete-invoice-modal")
                        |> JS.push("delete")
                      }
                      variant="destructive"
                      phx-disable-with="Usuwanie..."
                    >
                      Usuń
                    </.button>
                  </div>
                </.modal>
              </div>

              <div
                :if={@can_write_invoicing? and !!@invoice.ksef_number and not @cancelled?}
                class="absolute"
              >
                <.modal id="cancel-invoice-modal" on_cancel={hide_modal("cancel-invoice-modal")}>
                  <p>
                    Czy na pewno chcesz anulować fakturę <span class="font-semibold">{@invoice.invoice_number}</span>?
                    Wystawimy fakturę korygującą zerującą pozycje.
                  </p>
                  <div class="mt-6 flex justify-end gap-3">
                    <.button
                      type="button"
                      variant="secondary"
                      phx-click={hide_modal("cancel-invoice-modal")}
                    >
                      Wróć
                    </.button>
                    <.button
                      phx-click={
                        JS.exec("data-cancel", to: "#cancel-invoice-modal")
                        |> JS.push("cancel")
                      }
                      variant="destructive"
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
                  variant={if @invoice.share_token, do: "primary", else: "secondary"}
                  accent="teal"
                  size="small"
                  phx-click="create_share_link"
                >
                  <Lucideicons.share_2 />
                </.button>
              </span>
            </div>

            <InvoiceDetails.invoice_metadata>
              <InvoiceDetails.invoice_metadata_piece
                :if={is_nil(@invoice.invoice_number)}
                label={gettext("Invoice status")}
                value={gettext("Draft")}
                piece_id="invoice-status"
              />
              <InvoiceDetails.invoice_metadata_piece
                :if={!is_nil(@invoice.invoice_number)}
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
                value={@invoice.effective_sale_date}
                piece_id="sale-date"
              />
              <InvoiceDetails.invoice_metadata_piece
                label="Termin płatności"
                value={@invoice.effective_due_date}
                piece_id="due-date"
              />
            </InvoiceDetails.invoice_metadata>

            <InvoiceDetails.invoice_amount
              is_cost_invoice={false}
              amount={@latest_invoice_snapshot.amount}
            />
          <% end %>

          <InvoiceDetails.internal_note_form
            internal_note={@invoice.internal_note}
            can_write={@can_write_invoicing?}
            target={@myself}
          />

          <%= if @internal_notes != [] do %>
            <InvoiceDetails.invoice_notes internal_notes={@internal_notes} />
          <% end %>

          <InvoiceDetails.invoice_preview>
            <:subpreview
              :for={invoice <- @invoices_for_preview}
              invoice_number_label={invoice.invoice_number}
            >
              <Phoenix.Component.link href={Navigation.sales_invoice_pdf_path(invoice)} download>
                <InvoiceDetails.scalable_invoice_preview
                  id={"preview-#{invoice.id}"}
                  class="max-w-full min-w-0"
                >
                  <FirmowidUI.Invoicing.Components.SalesInvoice.sales_invoice
                    sales_invoice={invoice}
                    logo_url={assigns[:logo_url]}
                    currency_rate={Invoicing.get_currency_rate(invoice)}
                    show_vat={@show_vat_for_sales_invoice}
                    reference_invoice={invoice.reference_invoice}
                  />
                </InvoiceDetails.scalable_invoice_preview>
              </Phoenix.Component.link>
            </:subpreview>
          </InvoiceDetails.invoice_preview>
        </InvoiceDetails.aside>

        <InvoiceDetails.main>
          <.live_component
            :if={
              flag_enabled?(:analysis_dashboard, assigns) and
                (@invoice.skip_invoicing or @invoice.transactions != [])
            }
            module={FirmowidWeb.Analysis.Components.EntryCategories}
            id="invoice-categories"
            entry={@invoice}
            scope={@scope}
            feature_flags={@feature_flags}
          />
          <%= cond do %>
            <% @invoice.skip_invoicing -> %>
              <InvoiceDetails.invoice_skipped_view
                is_cost_invoice={false}
                can_write={@can_write_invoicing?}
              />
            <% not Enum.empty?(@invoice.transactions) -> %>
              <InvoiceDetails.transaction_match
                is_cost_invoice={false}
                transactions={@invoice.transactions}
              >
                <:status_action>
                  <.status_button
                    type="button"
                    phx-click="disconnect"
                    icon="hero-arrow-uturn-left-micro"
                  />
                </:status_action>
              </InvoiceDetails.transaction_match>
            <% true -> %>
              <InvoiceDetails.potential_transactions
                potential_transactions={@potential_transactions}
                is_cost_invoice={@is_cost_invoice}
                invoice={@invoice}
                can_write={@can_write_invoicing?}
              />
          <% end %>
        </InvoiceDetails.main>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("show_timeline", _params, socket) do
    {:noreply, assign(socket, show_timeline: true)}
  end

  def handle_event("hide_timeline", _params, socket) do
    {:noreply, assign(socket, show_timeline: false)}
  end

  def handle_event("save_internal_note", %{"internal_note" => note}, socket) do
    updated_invoice =
      SalesInvoice.update_internal_note!(socket.assigns.invoice, note, scope: socket.assigns.scope)

    invoice = %{socket.assigns.invoice | internal_note: updated_invoice.internal_note}

    {:noreply,
     assign(socket,
       invoice: invoice,
       invoices_for_preview: Enum.reverse([invoice | invoice.corrections])
     )}
  end

  defp show_timeline_button?(submission_info), do: SubmissionInfo.attempted?(submission_info)
end
