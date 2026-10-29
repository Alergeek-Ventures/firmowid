defmodule FirmowidWeb.Invoicing.Components.FilterBar do
  @moduledoc """
  Filter bar for the invoicing page.

  Renders tab navigation (Faktury / Transakcje / Nieprzypisane)
  with sub-filters (Opłacone/Nieopłacone for Faktury, Dopasowane/Bez dokumentu for Transakcje)
  and a "Grupy" button to switch back to dashboard mode.
  """
  use FirmowidWeb, :html

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

  attr :params, :map, required: true

  defp sub_filters(%{params: %{filter: :invoices}} = assigns) do
    ~H"""
    <.filter_pills divider>
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
    <.filter_pills divider>
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
