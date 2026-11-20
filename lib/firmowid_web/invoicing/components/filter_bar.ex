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

  attr :unmatched_count, :integer,
    default: nil,
    doc: "Unmatched entries of the list; their filter shows only above zero, or while it is open."

  def inbox_filters(assigns) do
    %{params: params, unmatched_count: unmatched_count} = assigns
    sides = side_filters(params.filter)

    # The unmatched entries get a fourth segment while there are any to match, and keep it
    # while it is open, so the list emptying by matching does not take the segment away.
    unmatched =
      if params.subfilter == :niedopasowane or (unmatched_count || 0) > 0,
        do: [{:niedopasowane, pgettext("list filter", "Unmatched"), nil, unmatched_count}],
        else: []

    segments =
      [{nil, pgettext("counterparty invoice filter", "All"), nil, nil}] ++
        Enum.map(sides, fn {key, {label, side}} -> {key, label, side, nil} end) ++ unmatched

    side = if Enum.any?(segments, &(elem(&1, 0) == params.subfilter)), do: params.subfilter

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
          :for={{subfilter, label, side, count} <- @segments}
          kind="unstyled"
          patch={build_url(@params.month, @params.filter, subfilter)}
          data-segment
          data-active={@side == subfilter}
          phx-mounted={subfilter == :niedopasowane && segment_in()}
          phx-remove={subfilter == :niedopasowane && segment_out()}
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
          <span
            :if={count && count > 0}
            class="flex h-4.5 min-w-4.5 items-center justify-center rounded-full bg-grey-700 px-1.25 text-caps-sm/none font-medium text-white"
          >
            {count}
          </span>
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

  # The unmatched segment comes and goes with the month on screen: it folds its width and
  # fades, so the bar shrinks smoothly instead of jumping.
  # The segment's own colour transition would win over this one, so this one is important.
  @segment_fold "overflow-hidden transition-[opacity,max-width,padding,color]! duration-300 ease-in-out motion-reduce:transition-none!"

  defp segment_in, do: JS.transition({@segment_fold, "max-w-0 px-0! opacity-0", "max-w-40 opacity-100"}, time: 300)

  defp segment_out, do: JS.transition({@segment_fold, "max-w-40 opacity-100", "max-w-0 px-0! opacity-0"}, time: 300)

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
