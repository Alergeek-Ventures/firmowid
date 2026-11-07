defmodule FirmowidWeb.Inbox.Components.SearchPalette do
  @moduledoc "Global, scope-authorized search for the inbox sidebar, hosted in every app layout."

  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button

  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoiceNavigation
  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:query, fn -> "" end)
     |> assign_new(:results, fn -> [] end)
     |> assign_new(:placeholder, fn -> placeholder(assigns) end)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = query |> String.trim() |> String.slice(0, 100)
    results = if query == "", do: [], else: search(query, socket.assigns)
    {:noreply, assign(socket, query: query, results: results)}
  end

  defp search(query, assigns) do
    destinations = destinations(assigns)

    places =
      destinations
      |> Enum.filter(&String.contains?(String.downcase(&1.label), String.downcase(query)))
      |> Enum.map(&Map.put(&1, :kind, pgettext("search result", "Place")))

    # Results whose label starts with the query come first, otherwise in kind order.
    Enum.sort_by(
      places ++
        invoices(query, destinations, assigns.scope) ++
        counterparties(query, destinations, assigns.scope) ++
        members(query, destinations, assigns.scope),
      &(not String.starts_with?(String.downcase(&1.label), String.downcase(query)))
    )
  end

  defp destinations(assigns) do
    Navigation.for_role(
      assigns.scope.actor.member.role,
      assigns.analysis_enabled,
      assigns.owner?,
      assigns.delegations_enabled
    )
  end

  # Employees only find places, so the hint promises no more than that.
  defp placeholder(assigns) do
    destination_ids = assigns |> destinations() |> Enum.map(& &1.id)

    if Enum.any?([:invoices, :counterparties, :team], &(&1 in destination_ids)),
      do: gettext("Search places, invoices, counterparties and people"),
      else: gettext("Search places")
  end

  defp invoices(query, destinations, scope) do
    if Enum.any?(destinations, &(&1.id == :invoices)) do
      # The limit applies to sales and cost invoices separately.
      %{query: query, limit: 5}
      |> Invoicing.search_invoices(scope)
      |> Enum.take(5)
      |> Enum.map(fn invoice ->
        cost? = is_struct(invoice, CostInvoice)

        %{
          label: invoice_label(invoice),
          icon_class: if(cost?, do: "text-rust-700", else: "text-teal-700"),
          kind: if(cost?, do: gettext("Cost invoice"), else: gettext("Sales invoice")),
          icon: "file-text",
          path:
            if(cost?,
              do: InvoiceNavigation.cost_invoice_show_path(invoice),
              else: InvoiceNavigation.sales_invoice_show_path(invoice)
            )
        }
      end)
    else
      []
    end
  end

  defp invoice_label(%CostInvoice{invoice_identifier: identifier}), do: identifier || gettext("Cost invoice")

  defp invoice_label(invoice), do: invoice.invoice_number || gettext("Draft")

  defp counterparties(query, destinations, scope) do
    if Enum.any?(destinations, &(&1.id == :counterparties)) do
      [search: query, limit: 5]
      |> Invoicing.list_counterparties!(scope: scope, load: [:display_label])
      |> Enum.map(fn counterparty ->
        %{
          label: counterparty.display_label,
          kind: pgettext("search result", "Counterparty"),
          icon: "building-2",
          path: ManagementNavigation.counterparty_path(counterparty.id)
        }
      end)
    else
      []
    end
  end

  defp members(query, destinations, scope) do
    if Enum.any?(destinations, &(&1.id == :team)) do
      [search: query, status: :active, limit: 5]
      |> Core.list_users!(scope: scope, load: [member: [:display_name]])
      |> Enum.map(fn user ->
        %{
          label: user.member.display_name,
          kind: pgettext("search result", "Person"),
          icon: "user",
          path: ManagementNavigation.employee_path(user.id)
        }
      end)
    else
      []
    end
  end

  defp result_icon_styles(result), do: Map.get(result, :icon_class, "text-grey-700")

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook=".SearchPalette" data-query={@query}>
      <.button
        variant="unstyled"
        id="app-search-trigger"
        type="button"
        class="hidden"
        phx-click={show_modal("app-search-modal")}
      >
        {gettext("Search")}
      </.button>
      <%!-- Pinned near the top, so the field stays put while results come and go. --%>
      <.modal id="app-search-modal" class="mbs-[10dvh] max-w-2xl self-start">
        <h2 id="app-search-modal-title" class="sr-only">{gettext("Search")}</h2>
        <p id="app-search-modal-description" class="sr-only">
          {gettext("Use arrow keys to choose a result, Enter to open, and Escape to close.")}
        </p>
        <.form for={%{}} id="app-search-form" phx-change="search" phx-target={@myself}>
          <.search_field
            id="app-search-query"
            name="query"
            value={@query}
            maxlength="100"
            autocomplete="off"
            role="combobox"
            aria-autocomplete="list"
            aria-expanded="true"
            aria-controls="app-search-results"
            phx-debounce="250"
            placeholder={@placeholder}
          />
        </.form>
        <div class="mbs-4 max-h-[50dvh] overflow-y-auto">
          <ul id="app-search-results" role="listbox" aria-label={gettext("Search results")}>
            <li
              :for={{result, index} <- Enum.with_index(@results)}
              id={"app-search-result-#{index}"}
              role="option"
              aria-selected="false"
              data-search-result
              class="rounded-md text-grey-900 aria-selected:bg-grey-100"
            >
              <Phoenix.Component.link
                navigate={result.path}
                tabindex="-1"
                class="flex items-center gap-3 rounded-md p-3 active:bg-grey-200 pointer-fine:hover:bg-grey-100"
              >
                <Lucideicons.render!
                  name={result.icon}
                  class={["size-4 shrink-0", result_icon_styles(result)]}
                  aria-hidden="true"
                />
                <span class="min-w-0 flex-1">
                  <span class="block text-sm wrap-break-word">{result.label}</span>
                  <span class="block text-xs text-grey-700">{result.kind}</span>
                </span>
              </Phoenix.Component.link>
            </li>
          </ul>
          <p :if={@query == ""} role="status" class="px-3 py-6 text-sm text-grey-700">
            {gettext("Start typing to find a place or record.")}
          </p>
          <p
            :if={@query != "" and @results == []}
            role="status"
            class="px-3 py-6 text-sm text-grey-700"
          >
            {gettext("No results. Try a different search.")}
          </p>
        </div>
        <p class="mbs-4 border-bs border-grey-200 pbs-3 text-xs text-grey-700 pointer-coarse:hidden">
          {gettext("↑ ↓ choose · Enter open · Esc close")}
        </p>
      </.modal>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SearchPalette">
        export default {
          mounted() {
            this.input = this.el.querySelector("input");
            this.modal = this.el.querySelector("#app-search-modal");
            // However the palette closes (Escape, the x, a click outside), focus goes back to its opener.
            this.restoreFocus = () => {
              if (this.opener?.isConnected) this.opener.focus();
            };
            this.modal.addEventListener("phx:hide-end", this.restoreFocus);
            this.index = -1;
            this.open = () => {
              this.opener = document.activeElement;
              this.el.querySelector("#app-search-trigger").click();
            };
            this.keydown = (event) => {
              if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === "k") {
                event.preventDefault();
                if (this.visible()) this.close();
                else this.open();
                return;
              }
              if (!this.visible()) return;
              // Escape while composing (IME) belongs to the composition, not to the modal.
              if (event.isComposing) {
                if (event.key === "Escape") event.stopImmediatePropagation();
                return;
              }
              if (event.key === "Escape") {
                event.preventDefault();
                event.stopImmediatePropagation();
                this.close();
              } else if (event.target === this.input && ["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) {
                event.preventDefault();
                const results = this.results();
                if (!results.length) return;
                if (event.key === "Enter") {
                  if (this.index >= 0) results[this.index].querySelector("a").click();
                } else {
                  this.index = this.index < 0
                    ? (event.key === "ArrowDown" ? 0 : results.length - 1)
                    : (this.index + (event.key === "ArrowDown" ? 1 : -1) + results.length) % results.length;
                  this.select();
                  results[this.index].scrollIntoView({block: "nearest"});
                }
              }
            };
            this.el.addEventListener("firmowid:search", this.open);
            window.addEventListener("keydown", this.keydown, true);
            this.input.addEventListener("input", () => {
              this.index = -1;
              this.select();
            });
            this.el.querySelector("form").addEventListener("submit", event => event.preventDefault());
            const hint = document.querySelector("[data-search-shortcut]");
            if (hint) hint.textContent = /Mac|iPhone|iPad/.test(navigator.platform) ? "⌘K" : "Ctrl K";
          },
          visible() { return this.el.querySelector("#app-search-modal").style.display === "block"; },
          results() {
            return this.input.value.trim().slice(0, 100) === this.el.dataset.query
              ? Array.from(this.el.querySelectorAll("[data-search-result]")) : [];
          },
          select() {
            this.el.querySelectorAll("[data-search-result]").forEach((item, index) => {
              item.setAttribute("aria-selected", String(index === this.index));
            });
            const selected = this.results()[this.index];
            if (selected) this.input.setAttribute("aria-activedescendant", selected.id);
            else this.input.removeAttribute("aria-activedescendant");
          },
          updated() {
            this.index = this.results().length ? 0 : -1;
            this.select();
          },
          close() {
            this.el.querySelector("#app-search-modal-container button").click();
          },
          destroyed() {
            window.removeEventListener("keydown", this.keydown, true);
            this.modal.removeEventListener("phx:hide-end", this.restoreFocus);
            this.el.removeEventListener("firmowid:search", this.open);
          }
        }
      </script>
    </div>
    """
  end
end
