defmodule FirmowidWeb.Components.Invoicing.CostInvoiceDetails do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Ksef
  alias FirmowidWeb.Components.Invoicing.InvoiceDetails, as: InvoiceDetails
  alias FirmowidWeb.Components.Invoicing.InvoiceTimeline

  attr :invoice, CostInvoice, required: true
  attr :preview_url, :string, required: true
  attr :preview_type, :atom, required: true
  attr :potential_transactions, :list, default: []
  attr :current_user, :map, required: true

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :is_cost_invoice, true)

    ~H"""
    <div id="invoice-show" class="flex flex-col">
      <InvoiceDetails.invoice_header
        is_cost_invoice={true}
        issue_date={@invoice.issue_date}
        party_display_name={@invoice.seller_display_name}
        description={@invoice.description}
      />

      <div class="flex flex-col lg:flex-row min-w-0 bg-white">
        <InvoiceDetails.aside>
          <%= if @show_timeline do %>
            <InvoiceTimeline.invoice_timeline invoice={@invoice} invoice_type={:cost} />
          <% else %>
            <div class="flex flex-row gap-4">
              <.button
                :if={CostInvoice.deletable?(@invoice)}
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
                :if={@preview_type not in [:none, :xml]}
                class={button_styles(%{color: "light_grey", size: "small", new: true})}
                href={@preview_url}
                download
              >
                <Lucideicons.download /><span class="hidden xl:inline">Pobierz</span>
              </.link>

              <.link
                :if={@preview_type == :xml}
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
              total_amount={Money.new(@invoice.currency, @invoice.total_amount)}
            />
          <% end %>

          <InvoiceDetails.invoice_preview :if={@preview_type != :none}>
            <%= case @preview_type do %>
              <% :pdf -> %>
                <a href={@preview_url} target="_blank">
                  <div
                    id="invoice-preview"
                    data-pdf-url={@preview_url}
                    phx-update="ignore"
                    phx-hook="PDFViewer"
                    class="w-full h-fit max-h-[80vh] overflow-x-hidden overflow-y-hidden bg-white"
                  >
                    <div class="min-w-[200px] min-h-[200px] flex items-center justify-center font-bold">
                      Ładowanie dokumentu...
                    </div>
                  </div>
                </a>
              <% :xml -> %>
                <InvoiceDetails.scalable_invoice_preview>
                  <div
                    id="invoice-preview"
                    data-fa3-url={@preview_url}
                    phx-update="ignore"
                    phx-hook=".FA3Viewer"
                    class="h-full w-[800px]"
                  >
                    <div class="mx-auto min-h-[200px] flex items-center justify-center font-bold">
                      Ładowanie dokumentu...
                    </div>
                  </div>
                </InvoiceDetails.scalable_invoice_preview>

                <script :type={Phoenix.LiveView.ColocatedHook} name=".FA3Viewer">
                  export default {
                    async mounted() {
                      const templateUrl = "/templates/kseffaktura_fa(3).xsl";
                      const fa3Url = this.el.getAttribute("data-fa3-url");

                      const [template, fa3Content] = await Promise.all([
                        fetch(templateUrl).then((response) => response.text()),
                        fetch(fa3Url).then((response) => response.text()),
                      ]);

                      const parser = new DOMParser();
                      const templateDoc = parser.parseFromString(template, "application/xml");
                      const fa3Doc = parser.parseFromString(fa3Content, "application/xml");

                      const htmlDocument = this.transformDocument(templateDoc, fa3Doc);

                      const iFrame = document.createElement("iframe");
                      iFrame.srcdoc = htmlDocument;
                      iFrame.className = "w-full h-full";
                      iFrame.addEventListener("load", () => {
                        iFrame.contentDocument.body.style.userSelect = "none";
                        iFrame.contentDocument.body.style.margin = "0";
                        iFrame.contentDocument.body.style.padding = "32px";

                        this.el.style.height = `${iFrame.contentDocument.body.scrollHeight + 32}px`;
                      });

                      this.el.replaceChildren(iFrame);
                    },

                    transformDocument(template, content) {
                      const processor = new XSLTProcessor();
                      processor.importStylesheet(template);
                      const resultDoc = processor.transformToDocument(content);

                      return new XMLSerializer().serializeToString(resultDoc);
                    },
                  };
                </script>
              <% :image -> %>
                <a href={@preview_url} target="_blank">
                  <div class="w-full h-full max-h-[80vh] overflow-x-hidden bg-black">
                    <img src={@preview_url} class="w-full h-full object-contain" />
                  </div>
                </a>
            <% end %>
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
                module={FirmowidWeb.CostInvoiceLive.Assistant}
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
