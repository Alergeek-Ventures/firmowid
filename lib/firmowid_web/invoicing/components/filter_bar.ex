defmodule FirmowidWeb.Invoicing.Components.FilterBar do
  @moduledoc """
  Filter bar for the invoicing page.

  Renders tab navigation (Faktury / Transakcje / Nieprzypisane)
  with sub-filters (Opłacone/Nieopłacone for Faktury, Dopasowane/Bez dokumentu for Transakcje)
  and a "Grupy" button to switch back to dashboard mode.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Invoicing.Utilities.Navigation

  attr :params, :map, required: true
  attr :pending_count, :integer, default: 0
  attr :is_month_closed, :boolean, default: false
  attr :is_month_touched, :boolean, default: false

  def filter_bar(assigns) do
    ~H"""
    <div class={[
      "mt-4 mb-3 flex items-center justify-between gap-6",
      !@is_month_touched && "hidden"
    ]}>
      <div class="flex items-center gap-6 max-md:w-full max-md:flex-wrap max-md:gap-y-3">
        <.filter_tabs label={gettext("Invoicing views")}>
          <:tab navigate={dashboard_url(@params.month)} active={@params.view_mode == :dashboard}>
            {gettext("Summary")}
          </:tab>
          <:tab
            navigate={filter_url(@params, :invoices)}
            active={@params.view_mode == :list && @params.filter == :invoices}
          >
            {gettext("Invoices")}
          </:tab>
          <:tab
            navigate={filter_url(@params, :transactions)}
            active={@params.view_mode == :list && @params.filter == :transactions}
          >
            {gettext("Transactions")}
          </:tab>
          <:tab
            navigate={filter_url(@params, :unmatched)}
            active={@params.view_mode == :list && @params.filter == :unmatched}
            count={@pending_count}
            class={unmatched_filter_styles(@params, @is_month_closed)}
            id="unmatched-filter"
            phx-hook="Confetti"
            data-confetti-enabled={if @is_month_closed, do: "true", else: "false"}
          >
            <%= if @is_month_closed do %>
              {gettext("Month closed")}
            <% else %>
              {pgettext("invoicing filter tab", "Unassigned")}
            <% end %>
          </:tab>
        </.filter_tabs>

        <.sub_filters
          :if={@params.view_mode == :list && @params.filter in [:invoices, :transactions]}
          params={@params}
        />
      </div>
    </div>
    """
  end

  @doc """
  Filters of the inbox sidebar layout, where invoices and transactions are
  separate places listing every month: the side of the invoice or the direction
  of the transaction. A status sub-filter opened from the summary stays visible
  while it is active.
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
    <div :if={@params.view_mode == :list} class="flex shrink-0 items-center gap-4 max-md:w-full">
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
      <.sub_filters
        :if={@params.subfilter in [:oplacone, :nieoplacone, :dopasowane, :bez_dokumentu]}
        params={@params}
        label={nil}
      />
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

  defp side_filters(_filter), do: []

  attr :params, :map, required: true
  attr :divider, :boolean, default: true
  attr :label, :any, default: :default

  defp sub_filters(%{params: %{filter: :invoices}} = assigns) do
    ~H"""
    <.filter_pills divider={@divider} label={@label}>
      <:pill
        navigate={subfilter_url(@params, :oplacone)}
        active={@params.subfilter == :oplacone}
      >
        {gettext("Paid")}
      </:pill>
      <:pill
        navigate={subfilter_url(@params, :nieoplacone)}
        active={@params.subfilter == :nieoplacone}
      >
        {gettext("Unpaid")}
      </:pill>
    </.filter_pills>
    """
  end

  defp sub_filters(%{params: %{filter: :transactions}} = assigns) do
    ~H"""
    <.filter_pills divider={@divider} label={@label}>
      <:pill
        navigate={subfilter_url(@params, :dopasowane)}
        active={@params.subfilter == :dopasowane}
      >
        {gettext("Matched")}
      </:pill>
      <:pill
        navigate={subfilter_url(@params, :bez_dokumentu)}
        active={@params.subfilter == :bez_dokumentu}
      >
        {gettext("Without document")}
      </:pill>
    </.filter_pills>
    """
  end

  defp sub_filters(assigns), do: ~H""

  defp dashboard_url(month) do
    Navigation.invoicing_index_path(%{
      month: month,
      filter: :all,
      subfilter: nil,
      view_mode: :dashboard
    })
  end

  defp filter_url(params, filter), do: build_url(params.month, filter, nil)

  defp subfilter_url(params, subfilter) do
    next_subfilter = if params.subfilter == subfilter, do: nil, else: subfilter
    build_url(params.month, params.filter, next_subfilter)
  end

  defp build_url(month, filter, subfilter) do
    Navigation.invoicing_index_path(%{
      month: month,
      filter: filter,
      subfilter: subfilter,
      view_mode: :list
    })
  end

  defp unmatched_filter_styles(params, is_month_closed) do
    [
      is_month_closed && params.filter != :unmatched && "text-grey-100!",
      params.filter == :unmatched && is_month_closed &&
        "bg-moss-200! border-moss-700! text-black!"
    ]
  end
end
