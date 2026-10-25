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
        <div class="flex items-center gap-4 max-md:grid max-md:w-full max-md:grid-cols-2 max-md:gap-2">
          <.link
            kind="unstyled"
            navigate={dashboard_url(@params.month)}
            aria-label="Podsumowanie"
            title="Podsumowanie"
            class={top_level_filter_styles(@params.view_mode == :dashboard)}
          >
            Podsumowanie
          </.link>
          <%= for {tab, label} <- [
            {:invoices, "Faktury"},
            {:transactions, "Transakcje"}
          ] do %>
            <.link
              kind="unstyled"
              navigate={filter_url(@params, tab)}
              class={top_level_filter_styles(@params.view_mode == :list && @params.filter == tab)}
            >
              {label}
            </.link>
          <% end %>

          <.link
            kind="unstyled"
            navigate={filter_url(@params, :unmatched)}
            class={unmatched_filter_styles(@params, @is_month_closed)}
            id="unmatched-filter"
            phx-hook="Confetti"
            data-confetti-enabled={if @is_month_closed, do: "true", else: "false"}
          >
            <%= if @pending_count != 0 do %>
              <span class="pointer-events-none absolute -top-3 left-full flex -translate-x-3 items-center justify-center overflow-hidden rounded-full border-2 border-grey-100 bg-rust-200 px-2 text-rust-700 max-md:right-0 max-md:left-auto max-md:translate-x-0">
                {@pending_count}
              </span>
            <% end %>
            <%= if @is_month_closed do %>
              Miesiąc zamknięty
            <% else %>
              Nieprzypisane
            <% end %>
          </.link>
        </div>

        <div
          :if={@params.view_mode == :list && @params.filter in [:invoices, :transactions]}
          class="flex items-center gap-6 max-md:w-full"
        >
          <div class="mx-2 h-7 w-px bg-grey-200 max-md:hidden"></div>
          <.sub_filters params={@params} />
        </div>
      </div>
    </div>
    """
  end

  attr :params, :map, required: true

  defp sub_filters(%{params: %{filter: :invoices}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 max-md:w-full">
      <span class="text-sm font-normal text-grey-700/70">Filtry:</span>
      <div class="flex items-center gap-2 max-md:flex-1">
        <.link
          kind="unstyled"
          navigate={subfilter_url(@params, :oplacone)}
          class={subfilter_styles(@params.subfilter == :oplacone)}
        >
          Opłacone
        </.link>
        <.link
          kind="unstyled"
          navigate={subfilter_url(@params, :nieoplacone)}
          class={subfilter_styles(@params.subfilter == :nieoplacone)}
        >
          Nieopłacone
        </.link>
      </div>
    </div>
    """
  end

  defp sub_filters(%{params: %{filter: :transactions}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 max-md:w-full">
      <span class="text-sm font-normal text-grey-700/70">Filtry:</span>
      <div class="flex items-center gap-2 max-md:flex-1">
        <.link
          kind="unstyled"
          navigate={subfilter_url(@params, :dopasowane)}
          class={subfilter_styles(@params.subfilter == :dopasowane)}
        >
          Dopasowane
        </.link>
        <.link
          kind="unstyled"
          navigate={subfilter_url(@params, :bez_dokumentu)}
          class={subfilter_styles(@params.subfilter == :bez_dokumentu)}
        >
          Bez dokumentu
        </.link>
      </div>
    </div>
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

  defp top_level_filter_styles(active?) do
    [
      "bg-grey-100 text-grey-700 relative inline-flex items-center justify-center rounded-lg px-3 py-1 text-center text-sm/6 font-normal uppercase transition-colors hover:bg-grey-200",
      active? && "bg-grey-700! text-white!"
    ]
  end

  defp unmatched_filter_styles(params, is_month_closed) do
    [
      "bg-grey-100 text-grey-700 relative inline-flex items-center justify-center rounded-lg px-3 py-1 text-center text-sm/6 font-normal uppercase transition-colors hover:bg-grey-200",
      params.view_mode == :list && params.filter == :unmatched && "bg-grey-700! text-white!",
      is_month_closed && params.filter != :unmatched && "text-grey-100!",
      params.filter == :unmatched && is_month_closed &&
        "bg-moss-200! border-moss-700! text-black!"
    ]
  end

  defp subfilter_styles(active?) do
    [
      "bg-grey-100 border-grey-200 text-grey-700 inline-flex h-8 items-center justify-center rounded-full border px-4 py-1.5 text-sm leading-none font-medium transition-colors max-md:flex-1",
      active? && "bg-grey-700! border-grey-700 text-white!",
      not active? && "hover:bg-grey-200"
    ]
  end
end
