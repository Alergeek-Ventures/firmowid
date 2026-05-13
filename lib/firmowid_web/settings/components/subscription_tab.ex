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
  attr :month, :any, required: true
  attr :worksheet, :any, required: true

  def subscription_tab(assigns) do
    ~H"""
    <%= if @worksheet do %>
      <div class="grid w-full gap-8 lg:grid-cols-2 lg:gap-x-12">
        <section class="space-y-4">
          <div class="space-y-2">
            <h2 class="text-grey-900 min-h-8 text-base leading-none font-semibold">
              Aktualny plan
            </h2>

            <p class="text-grey-700 max-w-prose text-sm leading-[1.35]">
              Plan przypisany do Twojej organizacji oraz limity, które obejmuje miesięczny snapshot rozliczeniowy.
            </p>
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <Helpers.settings_display_field label="Plan">
              <div class="flex flex-wrap items-center gap-2">
                <span>{@worksheet.selected_plan_label}</span>

                <span class={plan_badge_styles(@worksheet.selected_plan)}>
                  {plan_badge_label(@worksheet.selected_plan)}
                </span>
              </div>
            </Helpers.settings_display_field>

            <Helpers.settings_display_field label="Miesięczna opłata bazowa">
              <%= if @worksheet.base_fee_line do %>
                {@worksheet.base_fee_line.amount}
              <% else %>
                Brak opłaty bazowej
              <% end %>
            </Helpers.settings_display_field>
          </div>

          <div class="bg-grey-50 space-y-3 rounded-lg p-4">
            <h3 class="text-grey-900 text-sm leading-none font-medium">W cenie planu</h3>

            <div class="space-y-3">
              <%= for row <- @worksheet.usage_rows do %>
                <div class="flex items-start justify-between gap-4 text-sm leading-[1.35]">
                  <p class="text-grey-900 min-w-0">{row.label}</p>
                  <p class="text-grey-700 shrink-0 text-right">W cenie: {row.included_units}</p>
                </div>
              <% end %>
            </div>
          </div>

          <div
            :if={@worksheet.no_plan_note}
            class="bg-grey-50 text-grey-700 rounded-lg p-4 text-sm leading-[1.35]"
          >
            {@worksheet.no_plan_note}
          </div>

          <div
            :if={@worksheet.suggestion_rows != []}
            class="space-y-3 rounded-lg bg-orange-50 p-4"
          >
            <h3 class="text-grey-900 text-sm leading-none font-medium">Aktualne nadwyżki</h3>

            <div class="space-y-3">
              <%= for row <- @worksheet.suggestion_rows do %>
                <div class="flex items-start justify-between gap-4 text-sm leading-[1.35]">
                  <div class="min-w-0">
                    <p class="text-grey-900 font-medium">{row.label}</p>
                    <p :if={row.detail} class="text-grey-700">{row.detail}</p>
                  </div>

                  <p :if={row.amount} class="text-grey-900 shrink-0 text-right font-medium">
                    {row.amount}
                  </p>
                </div>
              <% end %>
            </div>
          </div>

          <div
            :if={@worksheet.suggestion_rows == []}
            class="bg-grey-50 text-grey-700 rounded-lg p-4 text-sm leading-[1.35]"
          >
            Brak dodatkowych nadwyżek względem planu w bieżącym miesiącu.
          </div>
        </section>

        <section class="space-y-4">
          <div class="space-y-2">
            <h2 class="text-grey-900 text-base leading-none font-semibold">Bieżące liczniki</h2>
            <p class="text-grey-700 max-w-prose text-sm leading-[1.35]">
              Orientacyjny podgląd na żywo dla {month_label(@month)}. Dane liczymy według tej samej logiki miesiąca rozliczeniowego, z której powstaje snapshot, ale ostateczne rozliczenie opiera się wyłącznie na utrwalonym snapshotcie.
            </p>
          </div>

          <div class="bg-grey-50 rounded-lg p-4">
            <div class="divide-grey-200 divide-y">
              <%= for row <- @worksheet.usage_rows do %>
                <div class="space-y-2 py-4 first:pt-0 last:pb-0">
                  <div class="flex items-start justify-between gap-4 text-sm leading-[1.35]">
                    <div class="min-w-0">
                      <p class="text-grey-900">{row.label}</p>
                      <p class="text-grey-700">{counter_context(row.key)}</p>
                    </div>

                    <div class="shrink-0 text-right">
                      <p class="text-grey-900 font-medium">{row.total_text}</p>
                      <p :if={row.over_limit > 0} class="text-orange-700">
                        +{row.over_limit} ponad limit
                      </p>
                    </div>
                  </div>

                  <div class="bg-grey-200 h-2 overflow-hidden rounded-full">
                    <div
                      class={counter_bar_fill_styles(row)}
                      style={"width: #{row.bar_width}%"}
                    >
                    </div>
                  </div>

                  <div class="text-grey-700 flex items-center justify-between gap-4 text-xs leading-[1.35]">
                    <span>W cenie: {row.included_units}</span>
                    <span>{row.usage_text}</span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </section>
      </div>
    <% else %>
      <div class="bg-grey-50 text-grey-700 rounded-lg p-4 text-sm leading-[1.35]">
        Ten podgląd jest dostępny tylko dla właściciela organizacji.
      </div>
    <% end %>
    """
  end

  defp month_label(%Date{} = month), do: Calendar.strftime(month, "%m.%Y")

  defp counter_context(:synced_bank_accounts), do: "Aktualnie podłączone konta z synchronizacją."

  defp counter_context(:active_non_owner_users), do: "Aktywni użytkownicy organizacji poza właścicielem."

  defp counter_context(:manual_external_invoices) do
    "Dokumenty dodane ręcznie w bieżącym miesiącu rozliczeniowym."
  end

  defp plan_badge_label(:no_plan), do: "brak planu"
  defp plan_badge_label(_plan), do: "aktywny"

  defp plan_badge_styles(:no_plan), do: "rounded-full bg-grey-200 px-3 py-1 text-sm/tight text-grey-700"

  defp plan_badge_styles(_plan) do
    "rounded-full bg-orange-100 px-3 py-1 text-sm/tight text-orange-700"
  end

  defp counter_bar_fill_styles(%{over_limit: over_limit}) when over_limit > 0, do: "h-full rounded-full bg-orange-500"

  defp counter_bar_fill_styles(_row), do: "h-full rounded-full bg-turquoise-700"
end
