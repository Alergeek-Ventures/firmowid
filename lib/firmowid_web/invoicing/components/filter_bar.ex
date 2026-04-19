defmodule FirmowidWeb.Invoicing.Components.FilterBar do
  @moduledoc """
  Filter bar for the invoicing page.

  Renders tab navigation (Faktury / Transakcje / Nieprzypisane)
  with sub-filters (Opłacone/Nieopłacone for Faktury, Dopasowane/Bez dokumentu for Transakcje)
  and a "Grupy" button to switch back to dashboard mode.
  """
  use FirmowidWeb, :html

  attr :params, :map, required: true
  attr :pending_count, :integer, default: 0
  attr :is_month_closed, :boolean, default: false
  attr :is_month_touched, :boolean, default: false

  def filter_bar(assigns) do
    ~H"""
    <div class={[
      "mt-4 mb-3 flex items-center justify-between gap-6 max-md:hidden",
      !@is_month_touched && "hidden"
    ]}>
      <div class="flex items-center gap-6">
        <div class="flex items-center gap-4">
          <.link
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
              navigate={filter_url(@params, tab)}
              class={top_level_filter_styles(@params.view_mode == :list && @params.filter == tab)}
            >
              {label}
            </.link>
          <% end %>

          <.link
            navigate={filter_url(@params, :unmatched)}
            class={unmatched_filter_styles(@params, @is_month_closed)}
            id="unmatched-filter"
            phx-hook="Confetti"
            data-confetti-enabled={if @is_month_closed, do: "true", else: "false"}
          >
            <%= if @pending_count != 0 do %>
              <span class="bg-orangeBg border-lightGreyBg text-orangeText pointer-events-none absolute -top-3 left-full flex -translate-x-3 items-center justify-center overflow-hidden rounded-full border-2 px-2">
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
          class="flex items-center gap-6"
        >
          <div class="bg-greyButtonBg mx-2 h-7 w-px"></div>
          <.sub_filters params={@params} />
        </div>
      </div>
    </div>
    """
  end

  attr :params, :map, required: true

  defp sub_filters(%{params: %{filter: :invoices}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="text-darkGrey/70 text-sm font-normal">Filtry:</span>
      <div class="flex items-center gap-2">
        <.link
          navigate={subfilter_url(@params, :oplacone)}
          class={subfilter_styles(@params.subfilter == :oplacone)}
        >
          Opłacone
        </.link>
        <.link
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
    <div class="flex items-center gap-3">
      <span class="text-darkGrey/70 text-sm font-normal">Filtry:</span>
      <div class="flex items-center gap-2">
        <.link
          navigate={subfilter_url(@params, :dopasowane)}
          class={subfilter_styles(@params.subfilter == :dopasowane)}
        >
          Dopasowane
        </.link>
        <.link
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

  defp dashboard_url(month), do: ~p"/fakturowanie?month=#{Date.to_iso8601(month)}&filter=all"

  defp filter_url(params, filter), do: build_url(params.month, filter, nil)

  defp subfilter_url(params, subfilter) do
    next_subfilter = if params.subfilter == subfilter, do: nil, else: subfilter
    build_url(params.month, params.filter, next_subfilter)
  end

  defp build_url(month, filter, subfilter) do
    query_parts = [
      "month=#{Date.to_iso8601(month)}",
      "filter=#{Atom.to_string(filter)}",
      "view=list"
    ]

    query_parts =
      if subfilter do
        query_parts ++ ["subfilter=#{Atom.to_string(subfilter)}"]
      else
        query_parts
      end

    "/fakturowanie?" <> Enum.join(query_parts, "&")
  end

  defp top_level_filter_styles(active?) do
    [
      "bg-lightGreyBg text-darkGrey relative inline-flex items-center justify-center rounded-lg px-3 py-1 text-center text-sm/6 font-normal uppercase transition-colors hover:bg-greyButtonBg",
      active? && "bg-darkGrey! text-white!"
    ]
  end

  defp unmatched_filter_styles(params, is_month_closed) do
    [
      "bg-lightGreyBg text-darkGrey relative inline-flex items-center justify-center rounded-lg px-3 py-1 text-center text-sm/6 font-normal uppercase transition-colors hover:bg-greyButtonBg",
      params.view_mode == :list && params.filter == :unmatched && "bg-darkGrey! text-white!",
      is_month_closed && params.filter != :unmatched && "text-lightGreyBg!",
      params.filter == :unmatched && is_month_closed &&
        "bg-greenBg! border-greenText! text-black!"
    ]
  end

  defp subfilter_styles(active?) do
    [
      "bg-lightGreyBg border-greyButtonBg text-darkGrey inline-flex h-8 items-center justify-center rounded-full border px-4 py-1.5 text-sm leading-none font-medium transition-colors",
      active? && "bg-darkGrey! border-darkGrey text-white!",
      not active? && "hover:bg-greyButtonBg"
    ]
  end
end
