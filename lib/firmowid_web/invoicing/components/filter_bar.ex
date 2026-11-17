defmodule FirmowidWeb.Invoicing.Components.FilterBar do
  @moduledoc """
  Filters of the invoicing lists: the side of the invoice or the direction of the
  transaction.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @doc """
  Filters of the lists of invoices and of transactions, which list every month:
  the side of the invoice or the direction of the transaction.
  """
  attr :params, :map, required: true

  def inbox_filters(assigns) do
    sides = side_filters(assigns.params.filter)
    side = if Keyword.has_key?(sides, assigns.params.subfilter), do: assigns.params.subfilter

    segments =
      [
        {nil, pgettext("counterparty invoice filter", "All"), nil}
        | Enum.map(sides, fn {key, {label, side}} -> {key, label, side} end)
      ]

    assigns = assign(assigns, segments: segments, side: side)

    ~H"""
    <div class="flex shrink-0 items-center gap-4 max-md:w-full">
      <%!-- A segmented control: the grey highlight slides under the chosen side. The hook moves
           it at the click, before the list changes; until the hook places it, the chosen
           segment is highlighted itself. --%>
      <nav
        id="side-filter"
        phx-hook=".SideFilter"
        aria-label={gettext("Filters")}
        class="relative flex h-9 items-center gap-0.5 overflow-hidden rounded-md border border-grey-200 max-md:w-full"
      >
        <span
          id="side-filter-highlight"
          phx-update="ignore"
          data-highlight
          aria-hidden="true"
          class="absolute inset-y-0 left-0 hidden rounded-[2px] bg-grey-200 duration-300 ease-out data-ready:block motion-safe:transition-[translate,width]"
        />
        <%!-- The hook's highlight takes over from the chosen segment's own. --%>
        <.link
          :for={{subfilter, label, side} <- @segments}
          kind="unstyled"
          patch={build_url(@params.month, @params.filter, subfilter)}
          data-segment
          data-active={@side == subfilter}
          aria-current={@side == subfilter && "page"}
          class="relative flex h-full items-center justify-center gap-1.5 rounded-[2px] px-3 text-sm font-medium whitespace-nowrap text-grey-700 transition-colors hover:text-grey-900 data-active:bg-grey-200 data-active:text-grey-900 max-md:flex-1 [:has(>[data-highlight][data-ready])>&]:bg-transparent!"
        >
          <%!-- Each side's dot takes the colour of its side of the books. --%>
          <span
            :if={side}
            class={[
              "size-2 shrink-0 rounded-full",
              side == :income && "bg-teal-700",
              side == :expenses && "bg-rust-700"
            ]}
          ></span>
          {label}
        </.link>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".SideFilter">
          export default {
            mounted() {
              this.highlight = this.el.querySelector("[data-highlight]");
              // Clicked, the highlight moves at once; the list follows when the server answers.
              this.el.addEventListener("click", event => {
                const segment = event.target.closest("[data-segment]");
                if (segment) this.place(segment, true);
              });
              // Fonts loading or the bar resizing move the segments, and the highlight with them.
              this.observer = new ResizeObserver(() => this.place(this.active(), false));
              this.observer.observe(this.el);
              this.place(this.active(), false);
            },
            updated() {
              this.place(this.active(), true);
            },
            destroyed() {
              this.observer.disconnect();
            },
            active() {
              return this.el.querySelector("[data-segment][data-active]");
            },
            place(segment, animate) {
              if (!segment) return;
              const highlight = this.highlight;
              if (!animate) highlight.style.transition = "none";
              highlight.style.width = `${segment.offsetWidth}px`;
              highlight.style.translate = `${segment.offsetLeft}px`;
              highlight.dataset.ready = "";
              if (!animate) {
                highlight.offsetWidth;
                highlight.style.transition = "";
              }
            }
          }
        </script>
      </nav>
    </div>
    """
  end

  defp side_filters(:invoices),
    do: [
      sprzedazowe: {pgettext("invoice side filter", "Sales"), :income},
      zakupowe: {pgettext("invoice side filter", "Purchase"), :expenses}
    ]

  defp side_filters(:transactions),
    do: [
      wplywy: {pgettext("transaction direction filter", "Incoming"), :income},
      wydatki: {pgettext("transaction direction filter", "Outgoing"), :expenses}
    ]

  defp build_url(month, filter, subfilter) do
    Navigation.invoicing_index_path(%{
      month: month,
      filter: filter,
      subfilter: subfilter
    })
  end
end
