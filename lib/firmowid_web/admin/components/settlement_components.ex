defmodule FirmowidWeb.Admin.Components.SettlementComponents do
  @moduledoc """
  Presentational components for the admin settlement LiveView.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Billing.PlanCatalog
  alias FirmowidWeb.Admin.Utilities.Navigation
  alias FirmowidWeb.Billing.Utilities.Worksheet

  attr :selected_month, :any, default: nil
  attr :active_months, :list, default: []

  def page_header(assigns) do
    ~H"""
    <div>
      <.month_picker
        :if={@selected_month}
        id="month"
        class="max-md:inline-flex"
        selected_date={@selected_month}
        active_months={@active_months}
      />
    </div>
    """
  end

  attr :selected_org, :map, required: true
  attr :status, :map, required: true
  attr :pending_billing_plan, :string, required: true

  def organization_panel(assigns) do
    ~H"""
    <section class="rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]">
      <div class="flex items-start justify-between">
        <.link
          kind="unstyled"
          navigate={Navigation.settlements_path()}
          class="text-grey-700 text-sm/snug hover:underline"
        >
          ← Wróć do listy organizacji
        </.link>
        <span class={status_chip_styles(@status)}>
          {status_chip_label(@status)}
        </span>
      </div>
      <div class="mt-4 space-y-1">
        <h2 class="text-grey-900 text-xl/tight font-medium">{@selected_org.name}</h2>
        <p class="text-grey-700 text-sm/snug">
          {status_description(@status)}
          <span :if={@status.kind == :snapshot}>
            Zamrożono {format_datetime(@status.frozen_at)}
          </span>
        </p>
      </div>

      <div class="border-grey-200 mt-6 grid gap-4 border-t pt-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(0,1fr)]">
        <div class="grid gap-4 text-sm/snug sm:grid-cols-2">
          <div class="space-y-1">
            <p class="text-grey-700">NIP</p>
            <p class="text-black">{@selected_org.nip}</p>
          </div>

          <div class="space-y-1">
            <p class="text-grey-700">Właściciel</p>
            <p class="text-black">{owner_display_name(@selected_org.owner)}</p>
          </div>

          <div class="space-y-1">
            <p class="text-grey-700">E-mail właściciela</p>
            <p class="break-all text-black">{present_text(@selected_org.owner.email)}</p>
          </div>

          <div class="space-y-1">
            <p class="text-grey-700">Telefon właściciela</p>
            <p class="break-all text-black">{present_text(@selected_org.owner.phone)}</p>
          </div>
        </div>

        <div class="space-y-3">
          <.form
            :let={plan_form}
            for={to_form(%{"billing_plan" => @pending_billing_plan}, as: "plan")}
            phx-change="change-current-plan"
            phx-submit="save-current-plan"
            class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"
          >
            <.input
              field={plan_form[:billing_plan]}
              type="select"
              label="Aktualny plan"
              options={plan_options()}
              new
            />

            <FirmowidWeb.DesignSystem.Components.Button.button
              type="submit"
              variant="primary"
              size="small"
              disabled={@pending_billing_plan == Atom.to_string(@selected_org.billing_plan)}
              class="justify-center sm:min-w-32"
            >
              Zapisz plan
            </FirmowidWeb.DesignSystem.Components.Button.button>
          </.form>

          <p class="text-grey-700 text-sm/snug">
            Zmiana planu działa na bieżący i przyszłe miesiące. Historyczny snapshot niżej pozostaje bez zmian.
          </p>
        </div>
      </div>
    </section>
    """
  end

  attr :selected_month, :any, required: true
  attr :status, :map, required: true
  attr :worksheet, :map, required: true
  attr :selected_org, :map, required: true

  def worksheet_panel(assigns) do
    ~H"""
    <section class="rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]">
      <div class="space-y-1">
        <h2 class="text-grey-900 text-lg/tight font-medium">Arkusz rozliczenia</h2>
        <p class="text-grey-700 text-sm/snug">{worksheet_intro(@selected_month, @status)}</p>
      </div>

      <div class="mt-8 grid gap-10 xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)]">
        <div class="space-y-8">
          <div class="space-y-4">
            <h3 class="text-grey-900 text-base/tight font-medium">Plan</h3>

            <div class="divide-grey-200 divide-y">
              <div class="flex items-center justify-between gap-4 py-3 text-sm/snug">
                <span class="text-grey-700">Plan dla wybranego miesiąca</span>
                <span class="font-medium text-black">{@worksheet.selected_plan_label}</span>
              </div>

              <div
                :if={@worksheet.base_fee_line}
                class="flex items-center justify-between gap-4 py-3 text-sm/snug"
              >
                <span class="text-grey-700">{@worksheet.base_fee_line.label}</span>
                <span class="font-medium text-black">{@worksheet.base_fee_line.amount}</span>
              </div>
            </div>

            <p :if={@worksheet.no_plan_note} class="text-grey-700 text-sm/snug">
              {@worksheet.no_plan_note}
            </p>
          </div>

          <div class="space-y-4">
            <h3 class="text-grey-900 text-base/tight font-medium">Interpretacja</h3>

            <div class="divide-grey-200 divide-y">
              <%= if @worksheet.suggestion_rows == [] do %>
                <div class="text-grey-700 py-3 text-sm/snug">
                  Brak dodatkowych pozycji do pokazania dla wybranego miesiąca.
                </div>
              <% else %>
                <div
                  :for={row <- @worksheet.suggestion_rows}
                  class="flex items-start justify-between gap-4 py-3 text-sm/snug"
                >
                  <div class="min-w-0">
                    <p class="font-medium text-black">{row.label}</p>
                    <p :if={row.detail} class="text-grey-700">{row.detail}</p>
                  </div>

                  <span :if={row.amount} class="shrink-0 font-medium text-black">
                    {row.amount}
                  </span>
                </div>
              <% end %>
            </div>
          </div>

          <div :if={@worksheet.selected_plan != :no_plan} class="space-y-4">
            <h3 class="text-grey-900 text-base/tight font-medium">
              Do zapłaty za {format_month(@selected_month)}
            </h3>

            <div class="divide-grey-200 divide-y">
              <div class="flex items-center justify-between gap-4 py-3 text-sm/snug">
                <span class="font-medium text-black">Razem</span>
                <div class="flex shrink-0 items-center gap-2">
                  <.billing_status_badge :if={@selected_org.on_trial?} status={:trial} />
                  <span class="font-medium text-black">{@worksheet.month_total_text}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="space-y-4">
          <h3 class="text-grey-900 text-base/tight font-medium">Liczniki użycia</h3>
          <div class="bg-grey-50 rounded-lg p-4">
            <div class="divide-grey-200 divide-y">
              <div :for={row <- @worksheet.usage_rows} class="space-y-2 py-4 first:pt-0 last:pb-0">
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
                  <div class={counter_bar_fill_styles(row)} style={"width: #{row.bar_width}%"}></div>
                </div>

                <div class="text-grey-700 flex items-center justify-between gap-4 text-xs leading-[1.35]">
                  <span>W cenie: {row.included_units}</span>
                  <span>{row.usage_text}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def empty_state(assigns) do
    ~H"""
    <section class="text-grey-700 rounded-lg bg-white p-6 text-sm/snug shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]">
      Brak organizacji do rozliczenia.
    </section>
    """
  end

  attr :status, :atom, required: true, values: [:trial]

  def billing_status_badge(assigns) do
    ~H"""
    <span class={billing_status_badge_styles(@status)}>
      {billing_status_badge_label(@status)}
    </span>
    """
  end

  defp plan_options do
    Enum.map(PlanCatalog.plans(), fn plan ->
      {Worksheet.plan_label(plan), Atom.to_string(plan)}
    end)
  end

  defp billing_status_badge_label(:trial), do: "okres próbny"

  defp billing_status_badge_styles(:trial) do
    "inline-flex items-center rounded-full bg-orange-100 px-3 py-1 text-sm/tight text-orange-700"
  end

  defp status_chip_label(%{kind: :live_preview}), do: "Na żywo"
  defp status_chip_label(%{kind: :snapshot}), do: "Snapshot historyczny"

  defp status_chip_styles(%{kind: :live_preview}) do
    "inline-flex items-center rounded-full px-3 py-1 text-sm/snug font-medium bg-grey-200 text-grey-900 text-center"
  end

  defp status_chip_styles(%{kind: :snapshot}) do
    "inline-flex items-center rounded-full px-3 py-1 text-sm/snug font-medium bg-orange-100 text-orange-700 text-center"
  end

  defp status_description(%{kind: :live_preview}) do
    "To orientacyjny podgląd bieżącego miesiąca. Ostateczne rozliczenie opiera się wyłącznie na utrwalonym snapshotcie."
  end

  defp status_description(%{kind: :snapshot}), do: "Dane pochodzą z utrwalonego snapshotu."

  defp worksheet_intro(selected_month, %{kind: :live_preview}) do
    "#{format_month(selected_month)} • orientacyjny podgląd liczony według tej samej logiki miesiąca rozliczeniowego, z której powstaje snapshot."
  end

  defp worksheet_intro(selected_month, %{kind: :snapshot}) do
    "#{format_month(selected_month)} • dane pochodzą z utrwalonego snapshotu."
  end

  defp format_month(%Date{} = month), do: Calendar.strftime(month, "%m.%Y")
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%d.%m.%Y %H:%M")

  defp counter_context(:synced_bank_accounts), do: "Aktualnie podłączone konta z synchronizacją."

  defp counter_context(:active_non_owner_users), do: "Aktywni użytkownicy organizacji poza właścicielem."

  defp counter_context(:manual_external_invoices) do
    "Dokumenty dodane ręcznie w bieżącym miesiącu rozliczeniowym."
  end

  defp counter_bar_fill_styles(%{over_limit: over_limit}) when over_limit > 0, do: "h-full rounded-full bg-orange-500"

  defp counter_bar_fill_styles(_row), do: "h-full rounded-full bg-turquoise-700"

  defp owner_display_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp owner_display_name(%{email: email}), do: present_text(email)
  defp owner_display_name(_owner), do: "—"

  defp present_text(nil), do: "—"

  defp present_text(value) do
    case value |> to_string() |> String.trim() do
      "" -> "—"
      text -> text
    end
  end
end
