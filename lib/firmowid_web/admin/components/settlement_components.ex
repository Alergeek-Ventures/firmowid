defmodule FirmowidWeb.Admin.Components.SettlementComponents do
  @moduledoc """
  Presentational components for the admin settlement LiveView.
  """

  use FirmowidWeb, :html

  alias Firmowid.Ash.Billing.PlanCatalog
  alias FirmowidWeb.Billing.Utilities.Worksheet

  attr :selected_org, :map, default: nil
  attr :status, :map, default: nil

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
      <div class="space-y-1">
        <h1 class="text-grey-900 text-2xl font-medium">Rozliczenie</h1>
        <p class="text-grey-700 max-w-2xl text-sm/snug">
          Orientacyjny podgląd bieżącego miesiąca albo widok utrwalonego snapshotu historycznego.
        </p>
      </div>

      <div :if={@selected_org} class="flex flex-col items-start gap-2 lg:items-end">
        <span class={status_chip_styles(@status)}>
          {status_chip_label(@status)}
        </span>

        <p class="text-grey-700 max-w-xs text-sm/snug lg:text-right">
          {status_description(@status)}
        </p>

        <p :if={@status.kind == :snapshot} class="text-grey-700 text-sm/snug lg:text-right">
          Zamrożono {format_datetime(@status.frozen_at)}
        </p>
      </div>
    </div>
    """
  end

  attr :selected_org, :map, required: true
  attr :selected_month, :any, required: true
  attr :organization_options, :list, required: true
  attr :month_options, :list, required: true
  attr :pending_billing_plan, :string, required: true

  def organization_panel(assigns) do
    ~H"""
    <section class="rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div class="space-y-1">
          <p class="text-grey-700 text-sm/snug">Wybrana organizacja</p>
          <h2 class="text-grey-900 text-xl/tight font-medium">{@selected_org.name}</h2>
        </div>

        <div class="flex flex-wrap gap-x-6 gap-y-3 text-sm/snug">
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
            <p class="break-all text-black">{owner_email(@selected_org.owner)}</p>
          </div>
        </div>
      </div>

      <div class="border-grey-200 mt-6 grid gap-4 border-t pt-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(0,1fr)]">
        <div class="grid gap-4 sm:grid-cols-2">
          <.form for={to_form(%{}, as: :filters)} phx-change="change-organization">
            <.input
              id="org_id"
              name="org_id"
              type="select"
              label="Organizacja"
              value={@selected_org.id}
              options={@organization_options}
              new
            />
          </.form>

          <.form for={to_form(%{}, as: :filters)} phx-change="change-month">
            <.input
              id="month"
              name="month"
              type="select"
              label="Miesiąc"
              value={Date.to_iso8601(@selected_month)}
              options={@month_options}
              new
            />
          </.form>
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
        </div>

        <div class="space-y-4">
          <div class="space-y-1">
            <h3 class="text-grey-900 text-base/tight font-medium">Fakty użycia</h3>
            <p class="text-grey-700 text-sm/snug">Surowe wartości dla wybranego miesiąca.</p>
          </div>

          <div class="divide-grey-200 divide-y">
            <div
              :for={row <- @worksheet.usage_rows}
              class="flex items-center justify-between gap-4 py-3 text-sm/snug"
            >
              <div class="min-w-0">
                <p class="font-medium text-black">{row.label}</p>
                <p class="text-grey-700">W cenie: {row.included_units}</p>
              </div>

              <div class="text-right">
                <p class="font-medium text-black">{row.count}</p>
                <p :if={row.over_limit > 0} class="text-grey-700">
                  +{row.over_limit} ponad limit
                </p>
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

  defp plan_options do
    Enum.map(PlanCatalog.plans(), fn plan ->
      {Worksheet.plan_label(plan), Atom.to_string(plan)}
    end)
  end

  defp status_chip_label(%{kind: :live_preview}), do: "Na żywo"
  defp status_chip_label(%{kind: :snapshot}), do: "Snapshot historyczny"

  defp status_chip_styles(%{kind: :live_preview}) do
    "inline-flex items-center rounded-full px-3 py-1 text-sm/snug font-medium bg-grey-200 text-grey-900"
  end

  defp status_chip_styles(%{kind: :snapshot}) do
    "inline-flex items-center rounded-full px-3 py-1 text-sm/snug font-medium bg-orange-100 text-orange-700"
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

  defp owner_display_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp owner_display_name(%{email: email}), do: present_text(email)
  defp owner_display_name(_owner), do: "—"

  defp owner_email(%{email: email}), do: present_text(email)
  defp owner_email(_owner), do: "—"

  defp present_text(nil), do: "—"

  defp present_text(value) do
    case value |> to_string() |> String.trim() do
      "" -> "—"
      text -> text
    end
  end
end
