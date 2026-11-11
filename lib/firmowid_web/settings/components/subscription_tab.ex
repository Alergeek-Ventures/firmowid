defmodule FirmowidWeb.Settings.Components.SubscriptionTab do
  @moduledoc """
  Function component for the owner-only subscription tab.
  """

  use FirmowidWeb, :html

  alias FirmowidWeb.Settings.Components.Helpers

  @doc """
  Renders the owner-only subscription tab.
  """
  @spec subscription_tab(map()) :: Phoenix.LiveView.Rendered.t()
  attr :worksheet, :any, required: true

  attr :standalone, :boolean, default: false

  def subscription_tab(assigns) do
    ~H"""
    <%= if @worksheet do %>
      <div class={[
        "grid w-full gap-8",
        !@standalone && "lg:grid-cols-2 lg:gap-x-12"
      ]}>
        <section class="space-y-4">
          <div class="space-y-2">
            <h2 class="min-h-8 text-base leading-none font-semibold text-grey-900">
              {gettext("Current plan")}
            </h2>

            <p class="max-w-prose text-sm/snug text-grey-700">
              {gettext("The plan assigned to your organization and what it includes.")}
            </p>
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <Helpers.settings_display_field label={gettext("Plan")}>
              <div class="flex flex-wrap items-center gap-2">
                <span>{@worksheet.selected_plan_label}</span>

                <span class={plan_badge_styles(@worksheet.selected_plan)}>
                  {plan_badge_label(@worksheet.selected_plan)}
                </span>
              </div>
            </Helpers.settings_display_field>

            <Helpers.settings_display_field label={gettext("Monthly fee (net)")}>
              {@worksheet.monthly_price_text}
            </Helpers.settings_display_field>
          </div>

          <div class="space-y-3 rounded-lg bg-grey-50 p-4">
            <h3 class="text-sm leading-none font-medium text-grey-900">
              {gettext("Included in the plan")}
            </h3>

            <div class="space-y-3">
              <%= for row <- @worksheet.usage_rows do %>
                <div class="flex items-start justify-between gap-4 text-sm/snug">
                  <p class="min-w-0 text-grey-900">{row.label}</p>
                  <p class="shrink-0 text-right text-grey-700">
                    {gettext("Included in the price: %{units}", units: row.limit_text)}
                  </p>
                </div>
              <% end %>
            </div>
          </div>

          <div :if={@worksheet.over_limit?} class="space-y-2 rounded-lg bg-rust-100 p-4 text-sm/snug">
            <h3 class="leading-none font-medium text-grey-900">
              {gettext("Above the plan limits")}
            </h3>

            <p class="text-grey-700">
              {gettext("Your current usage fits the %{plan} plan (%{price} net / mo.).",
                plan: @worksheet.fitting_plan_label,
                price: @worksheet.fitting_plan_price_text
              )}
            </p>
          </div>

          <div
            :if={!@worksheet.over_limit?}
            class="rounded-lg bg-grey-50 p-4 text-sm leading-[1.35] text-grey-700"
          >
            {gettext("Your current usage is within the plan limits.")}
          </div>
        </section>

        <section class="space-y-4">
          <div class="space-y-2">
            <h2 class="text-base leading-none font-semibold text-grey-900">
              {gettext("Current counters")}
            </h2>
            <p class="max-w-prose text-sm/snug text-grey-700">
              {gettext("What your organization uses right now.")}
            </p>
          </div>

          <div class="rounded-lg bg-grey-50 p-4">
            <div class="divide-y divide-grey-200">
              <%= for row <- @worksheet.usage_rows do %>
                <div class="space-y-2 py-4 first:pt-0 last:pb-0">
                  <div class="flex items-start justify-between gap-4 text-sm/snug">
                    <div class="min-w-0">
                      <p class="text-grey-900">{row.label}</p>
                      <p class="text-grey-700">{row.context}</p>
                    </div>

                    <div class="shrink-0 text-right">
                      <p class="font-medium text-grey-900">{row.total_text}</p>
                      <p :if={row.over_limit > 0} class="text-rust-700">
                        {gettext("+%{count} over the limit", count: row.over_limit)}
                      </p>
                    </div>
                  </div>

                  <div :if={row.bar_width} class="h-2 overflow-hidden rounded-full bg-grey-200">
                    <div
                      class={counter_bar_fill_styles(row)}
                      style={"width: #{row.bar_width}%"}
                    >
                    </div>
                  </div>

                  <div class="flex items-center justify-between gap-4 text-xs/snug text-grey-700">
                    <span>{gettext("Included in the price: %{units}", units: row.limit_text)}</span>
                    <span :if={row.usage_text}>{row.usage_text}</span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </section>
      </div>
    <% else %>
      <div class="rounded-lg bg-grey-50 p-4 text-sm leading-[1.35] text-grey-700">
        {gettext("This preview is available only to the organization owner.")}
      </div>
    <% end %>
    """
  end

  defp plan_badge_label(:no_plan), do: gettext("no plan")
  defp plan_badge_label(_plan), do: gettext("active")

  defp plan_badge_styles(:no_plan), do: "rounded-full bg-grey-200 px-3 py-1 text-sm/tight text-grey-700"

  defp plan_badge_styles(_plan) do
    "rounded-full bg-rust-100 px-3 py-1 text-sm/tight text-rust-700"
  end

  defp counter_bar_fill_styles(%{over_limit: over_limit}) when over_limit > 0, do: "h-full rounded-full bg-rust-500"

  defp counter_bar_fill_styles(_row), do: "h-full rounded-full bg-teal-700"
end
