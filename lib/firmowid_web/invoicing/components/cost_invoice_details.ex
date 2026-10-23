defmodule FirmowidWeb.Invoicing.Components.CostInvoiceDetails do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Invoicing.Components.StatusButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Ksef
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Components.InvoiceDownloadModal
  alias FirmowidWeb.Invoicing.Components.InvoiceTimeline
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       show_timeline: false,
       is_cost_invoice: true
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(
        :can_write_invoicing?,
        Ash.can?({CostInvoice, :toggle_skip}, assigns.current_user)
      )

    socket =
      if Map.has_key?(assigns, :invoice) do
        assign(
          socket,
          :invoices_for_preview,
          Enum.reverse([assigns.invoice | assigns.invoice.correction_invoices])
        )
      else
        socket
      end

    {:ok, socket}
  end

  attr :invoice, CostInvoice, required: true
  attr :potential_transactions, :list, default: []
  attr :current_user, :map, required: true
  attr :return_to, :string, default: nil
  attr :scope, :map, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div id="invoice-show" class="flex flex-col">
      <InvoiceDetails.invoice_header
        variant={invoice_source_badge_variant(@invoice)}
        is_cost_invoice={true}
        issue_date={@invoice.issue_date}
        party_display_name={@invoice.effective_seller_display_name}
        description={@invoice.description}
        return_to={@return_to}
      />

      <div class="flex min-w-0 flex-col bg-white lg:flex-row">
        <InvoiceDetails.aside>
          <div id="aside-dynamic-content">
            <%= if @show_timeline do %>
              <InvoiceTimeline.invoice_timeline
                invoice={@invoice}
                invoice_type={:cost}
              />
            <% else %>
              <div class="flex flex-row gap-4">
                <.live_component
                  :if={downloadable_as_pdf?(@invoice)}
                  module={InvoiceDownloadModal}
                  id={"cost-download-#{@invoice.id}"}
                  download_path={Navigation.cost_invoice_pdf_path(@invoice)}
                  trigger_variant="secondary"
                  trigger_size="small"
                  button_label="Pobierz PDF do druku"
                />

                <.link
                  :if={!downloadable_as_pdf?(@invoice)}
                  kind="button"
                  variant="secondary"
                  size="small"
                  external={@invoice.blob && @invoice.blob.url}
                  download
                >
                  <Lucideicons.download /><span class="hidden xl:inline">Pobierz</span>
                </.link>

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

                <div
                  :if={@can_write_invoicing? and @invoice.is_deletable}
                  class="absolute"
                >
                  <.modal id="delete-invoice-modal" on_cancel={hide_modal("delete-invoice-modal")}>
                    <p>
                      Czy na pewno chcesz usunąć fakturę <span class="font-semibold">{@invoice.invoice_identifier}</span>?
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

                <.link
                  :if={@invoice.ksef_number != nil}
                  external={Ksef.invoice_url!(@invoice, scope: @scope)}
                  target="_blank"
                  rel="noopener noreferrer"
                  kind="button"
                  variant="secondary"
                  size="small"
                >
                  <Lucideicons.database /><span class="hidden xl:inline">Otwórz w KSeF</span>
                </.link>

                <.button
                  :if={@invoice.ksef_number != nil}
                  class="ml-auto"
                  variant="secondary"
                  size="small"
                  phx-click="show_timeline"
                  phx-target={@myself}
                >
                  Historia faktury
                </.button>
              </div>

              <InvoiceDetails.invoice_metadata>
                <InvoiceDetails.invoice_metadata_piece
                  label="Numer faktury"
                  value={@invoice.invoice_identifier}
                  piece_id="invoice-identifier"
                />
                <InvoiceDetails.invoice_metadata_piece
                  :if={@invoice.ksef_number != nil}
                  label="Identyfikator KSeF"
                  value={@invoice.ksef_number}
                  piece_id="ksef-id"
                />

                <InvoiceDetails.invoice_metadata_piece
                  :if={@invoice.original_invoice_ksef_number != nil}
                  label="Identyfikator KSeF faktury korygowanej"
                  value={@invoice.original_invoice_ksef_number}
                  piece_id="original-invoice-ksef-id"
                />

                <InvoiceDetails.invoice_metadata_piece
                  label="Sprzedawca"
                  value={@invoice.seller}
                  piece_id="seller"
                  multiline
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
                is_cost_invoice={true}
                amount={@invoice.effective_amount}
              />

              <InvoiceDetails.internal_note_form
                internal_note={@invoice.internal_note}
                can_write={@can_write_invoicing?}
                target={@myself}
              />
            <% end %>
          </div>

          <InvoiceDetails.invoice_preview>
            <:subpreview
              :for={invoice <- @invoices_for_preview}
              invoice_number_label={invoice.invoice_identifier}
            >
              <.preview invoice={invoice} />
            </:subpreview>
          </InvoiceDetails.invoice_preview>
        </InvoiceDetails.aside>

        <InvoiceDetails.main>
          <%= cond do %>
            <% @invoice.skip_invoicing -> %>
              <InvoiceDetails.invoice_skipped_view
                is_cost_invoice={@is_cost_invoice}
                can_write={@can_write_invoicing?}
              />
            <% not Enum.empty?(@invoice.transactions) -> %>
              <InvoiceDetails.transaction_match
                is_cost_invoice={@is_cost_invoice}
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
          <.live_component
            :if={flag_enabled?(:analysis_dashboard, assigns)}
            module={FirmowidWeb.Analysis.Components.EntryCategories}
            id="invoice-categories"
            entry={@invoice}
            scope={@scope}
            feature_flags={@feature_flags}
          />
        </InvoiceDetails.main>
      </div>
    </div>
    """
  end

  attr :invoice, CostInvoice, required: true

  defp preview(assigns) do
    invoice = assigns.invoice
    preview_type = preview_type(invoice.blob)
    assigns = %{preview_url: invoice.blob && invoice.blob.url, id: invoice.id}

    case preview_type do
      :pdf ->
        ~H"""
        <.link
          kind="unstyled"
          external={@preview_url}
          target="_blank"
        >
          <div
            id={"invoice-preview-#{@id}"}
            data-pdf-url={@preview_url}
            phx-update="ignore"
            phx-hook="PDFViewer"
            class="h-fit max-h-[80vh] w-full overflow-hidden bg-white"
          >
            <div class="flex w-full items-center justify-center p-8 font-bold">
              Ładowanie dokumentu...
            </div>
          </div>
        </.link>
        """

      :xml ->
        ~H"""
        <InvoiceDetails.scalable_invoice_preview id={"invoice-scaler-#{@id}"}>
          <div
            id={"invoice-preview-#{@id}"}
            data-fa3-url={@preview_url}
            phx-update="ignore"
            phx-hook=".FA3Viewer"
            class="size-full"
          >
            <div class="flex w-full items-center justify-center p-8 font-bold">
              Ładowanie dokumentu...
            </div>
          </div>
        </InvoiceDetails.scalable_invoice_preview>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".FA3Viewer">
          export default {
            async mounted() {
              const templateUrl = "/templates/kseffaktura_fa(3).xsl";
              const fa3Url = this.el.dataset.fa3Url;

              const [template, fa3Content] = await Promise.all([
                fetch(templateUrl).then((response) => response.text()),
                fetch(fa3Url).then((response) => response.text()),
              ]);

              const fa3Html = this.transformDocument(template, fa3Content);
              fa3Html.body.style.userSelect = "none";
              fa3Html.body.style.margin = "0";
              fa3Html.body.style.padding = "32px";
              const srcDoc = this.serializeDocument(fa3Html);

              const iframe = document.createElement("iframe");
              iframe.className = "w-[800px] h-full";
              iframe.srcdoc = srcDoc;
              this.el.replaceChildren(iframe);

              iframe.addEventListener("load", () => {
                this.el.style.height = `${iframe.contentDocument.body.scrollHeight + 32}px`;
              }, { once: true });
            },

            serializeDocument(document) {
              return new XMLSerializer().serializeToString(document);
            },

            transformDocument(template, content) {
              const parser = new DOMParser();
              template = parser.parseFromString(template, "application/xml");
              content = parser.parseFromString(content, "application/xml");

              const processor = new XSLTProcessor();
              processor.importStylesheet(template);
              return processor.transformToDocument(content);
            },
          };
        </script>
        """

      :image ->
        ~H"""
        <.link
          kind="unstyled"
          external={@preview_url}
          target="_blank"
        >
          <div class="size-full max-h-[80vh] overflow-x-hidden bg-black">
            <img src={@preview_url} class="size-full object-contain" />
          </div>
        </.link>
        """

      :none ->
        ~H"""
        <div class="flex w-full items-center justify-center p-8 font-bold">
          Brak podglądu
        </div>
        """
    end
  end

  defp preview_type(nil), do: :none

  defp preview_type(%{blob_path: path}) when is_binary(path) do
    cond do
      String.ends_with?(path, ".pdf") -> :pdf
      String.ends_with?(path, ".xml") -> :xml
      true -> :image
    end
  end

  defp downloadable_as_pdf?(%{ksef_number: ksef_number}) when not is_nil(ksef_number), do: true
  defp downloadable_as_pdf?(%{blob: blob}), do: preview_type(blob) == :pdf
  defp downloadable_as_pdf?(_invoice), do: false

  @impl true
  def handle_event("show_timeline", _params, socket) do
    {:noreply, assign(socket, show_timeline: true)}
  end

  def handle_event("hide_timeline", _params, socket) do
    {:noreply, assign(socket, show_timeline: false)}
  end

  def handle_event("save_internal_note", %{"internal_note" => internal_note}, socket) do
    case CostInvoice.update_internal_note(socket.assigns.invoice, internal_note, scope: socket.assigns.scope) do
      {:ok, %CostInvoice{} = updated_invoice} ->
        invoice = %{socket.assigns.invoice | internal_note: updated_invoice.internal_note}

        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> assign(
           :invoices_for_preview,
           Enum.reverse([
             invoice
             | invoice.correction_invoices
           ])
         )}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się zapisać komentarza")}
    end
  end
end
