defmodule FirmowidWeb.Invoicing.Components.CostInvoiceDetails do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Ksef
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Components.InvoiceTimeline

  @impl true
  def mount(socket) do
    {:ok, assign(socket, chat: false, show_timeline: false, is_cost_invoice: true)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:invoices_for_preview, Enum.reverse([assigns.invoice | assigns.invoice.correction_invoices]))

    {:ok, socket}
  end

  attr :invoice, CostInvoice, required: true
  attr :potential_transactions, :list, default: []
  attr :current_user, :map, required: true
  attr :scope, :map, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div id="invoice-show" class="flex flex-col">
      <InvoiceDetails.invoice_header
        is_cost_invoice={true}
        issue_date={@invoice.issue_date}
        party_display_name={@invoice.effective_seller_display_name}
        description={@invoice.description}
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
                <%!-- TODO: BUG-9 - Add confirmation modal before delete, matching the pattern
                     in sales_invoice_details.ex (which uses a modal with explicit confirm/cancel). --%>
                <.button
                  :if={@invoice.is_deletable}
                  phx-click="delete"
                  color="light_grey"
                  size="small"
                  new={true}
                >
                  <.icon name="hero-trash-solid" class="size-4" />
                  <span class="hidden xl:inline">
                    Usuń
                  </span>
                </.button>

                <.link
                  :if={@invoice.ksef_number == nil}
                  class={button_styles(%{color: "light_grey", size: "small", new: true})}
                  href={@invoice.blob && @invoice.blob.url}
                  download
                >
                  <Lucideicons.download /><span class="hidden xl:inline">Pobierz</span>
                </.link>

                <.link
                  :if={@invoice.ksef_number != nil}
                  class={button_styles(%{color: "light_grey", size: "small", new: true})}
                  href={Ksef.invoice_url!(@invoice)}
                  target="_blank"
                >
                  <Lucideicons.database /><span class="hidden xl:inline">Otwórz w KSeF</span>
                </.link>

                <.button
                  :if={@invoice.ksef_number != nil}
                  class="ml-auto"
                  color="light_grey"
                  size="small"
                  new={true}
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
                  value={@invoice.sale_date}
                  piece_id="sale-date"
                />
                <InvoiceDetails.invoice_metadata_piece
                  label="Termin płatności"
                  value={@invoice.due_date}
                  piece_id="due-date"
                />
              </InvoiceDetails.invoice_metadata>

              <InvoiceDetails.invoice_amount
                is_cost_invoice={true}
                total_amount={Money.new(@invoice.effective_currency, @invoice.effective_total_amount)}
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
              <InvoiceDetails.invoice_skipped_view is_cost_invoice={@is_cost_invoice} />
            <% not Enum.empty?(@invoice.transactions) -> %>
              <InvoiceDetails.transaction_match
                is_cost_invoice={@is_cost_invoice}
                transactions={@invoice.transactions}
              />
            <% @chat -> %>
              <.live_component
                module={FirmowidWeb.Invoicing.CostInvoices.Components.Assistant}
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

  attr :invoice, CostInvoice, required: true

  defp preview(assigns) do
    invoice = assigns.invoice
    preview_type = preview_type(invoice.blob)
    assigns = %{preview_url: invoice.blob && invoice.blob.url, id: invoice.id}

    case preview_type do
      :pdf ->
        ~H"""
        <a href={@preview_url} target="_blank">
          <div
            id="invoice-preview"
            data-pdf-url={@preview_url}
            phx-update="ignore"
            phx-hook="PDFViewer"
            class="h-fit max-h-[80vh] w-full overflow-x-hidden overflow-y-hidden bg-white"
          >
            <div class="flex w-full items-center justify-center p-8 font-bold">
              Ładowanie dokumentu...
            </div>
          </div>
        </a>
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
        <a href={@preview_url} target="_blank">
          <div class="size-full max-h-[80vh] overflow-x-hidden bg-black">
            <img src={@preview_url} class="size-full object-contain" />
          </div>
        </a>
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
end
