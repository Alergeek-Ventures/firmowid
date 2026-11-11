defmodule FirmowidWeb.Admin.Components.SettlementComponents do
  @moduledoc """
  Presentational components for the admin settlement LiveView.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Billing.PlanCatalog
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
    <section class="rounded-lg bg-white p-6 shadow-card">
      <div class="flex items-start justify-between">
        <.link
          kind="unstyled"
          navigate={Navigation.settlements_path()}
          class="text-sm/snug text-grey-700 hover:underline"
        >
          {gettext("← Back to the organization list")}
        </.link>
        <div class="flex flex-wrap items-center justify-end gap-3">
          <%!-- A blocked owner (see the User `:access_block` calculation) cannot be signed in. --%>
          <.form
            :if={@selected_org.billing_plan != :no_plan}
            for={%{}}
            id="impersonation-form"
            action={Navigation.impersonation_path(@selected_org.id)}
            method="post"
          >
            <FirmowidUI.Components.Button.button type="submit" variant="outline" size="small">
              {gettext("Sign in as owner")}
            </FirmowidUI.Components.Button.button>
          </.form>
          <span class={status_chip_styles(@status)}>
            {status_chip_label(@status)}
          </span>
        </div>
      </div>
      <div class="mt-4 space-y-1">
        <h2 class="text-xl/tight font-medium text-grey-900">{@selected_org.name}</h2>
        <p class="text-sm/snug text-grey-700">
          {status_description(@status)}
          <span :if={@status.kind == :snapshot}>
            {gettext("Frozen %{date}", date: format_datetime(@status.frozen_at))}
          </span>
        </p>
      </div>

      <div class="mt-6 grid gap-4 border-t border-grey-200 pt-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(0,1fr)]">
        <div class="grid gap-4 text-sm/snug sm:grid-cols-2">
          <div class="space-y-1">
            <p class="text-grey-700">NIP</p>
            <p class="text-black">{@selected_org.nip}</p>
          </div>

          <div class="space-y-1">
            <p class="text-grey-700">{gettext("Owner")}</p>
            <p class="text-black">{owner_display_name(@selected_org.owner)}</p>
          </div>

          <div class="space-y-1">
            <p class="text-grey-700">{gettext("Owner email")}</p>
            <p class="break-all text-black">{present_text(@selected_org.owner.email)}</p>
          </div>

          <div class="space-y-1">
            <p class="text-grey-700">{gettext("Owner phone")}</p>
            <p class="break-all text-black">{present_text(@selected_org.owner.member.phone)}</p>
          </div>
        </div>

        <div class="space-y-3">
          <.form
            :let={plan_form}
            for={to_form(%{"billing_plan" => @pending_billing_plan}, as: "plan")}
            id="current-plan-form"
            phx-change="change-current-plan"
            phx-submit="save-current-plan"
            class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end"
          >
            <.input
              field={plan_form[:billing_plan]}
              type="select"
              label={gettext("Current plan")}
              options={plan_options()}
            />

            <FirmowidUI.Components.Button.button
              type="submit"
              variant="primary"
              size="small"
              disabled={@pending_billing_plan == Atom.to_string(@selected_org.billing_plan)}
              class="justify-center sm:min-w-32"
            >
              {gettext("Save plan")}
            </FirmowidUI.Components.Button.button>
          </.form>

          <p class="text-sm/snug text-grey-700">
            {gettext(
              "A plan change applies to the current and future months. The historical snapshot below stays unchanged."
            )}
          </p>
        </div>
      </div>
    </section>
    """
  end

  attr :activity, :map, required: true

  def activity_panel(assigns) do
    ~H"""
    <section class="rounded-lg bg-white p-6 shadow-card">
      <h2 class="text-lg/tight font-medium text-grey-900">
        {gettext("Organization activity")}
      </h2>
      <p class="mt-1 text-sm/snug text-grey-700">
        {gettext(
          "Recorded events in the organization, independent of the selected billing month. The numbers cover the last 30 days (rolling 720 hours). These are not sign-in dates."
        )}
      </p>
      <.trace_rows rows={activity_rows(@activity)} />
      <p class="mt-3 text-sm/snug text-grey-700">{last_sign_in_text(@activity.last_sign_in)}</p>

      <h3 class="mt-6 text-base/tight font-medium text-grey-900">{gettext("Paid features")}</h3>
      <p class="mt-1 text-sm/snug text-grey-700">
        {gettext(
          "Features the pricing page offers only in paid plans. Today every plan can use them."
        )}
      </p>
      <.trace_rows rows={paid_feature_rows(@activity)} />
    </section>
    """
  end

  attr :rows, :list, required: true

  defp trace_rows(assigns) do
    ~H"""
    <div class="mt-4 divide-y divide-grey-200 text-sm/snug">
      <div :for={{label, trace} <- @rows} class="flex flex-wrap justify-between gap-3 py-3">
        <span class="text-grey-900">{label}</span>
        <span class="text-grey-700">
          {gettext("Last: %{last} · Last 30 days: %{count}",
            last: format_activity_datetime(trace.last_at),
            count: trace.count_30_days
          )}
        </span>
      </div>
    </div>
    """
  end

  defp activity_rows(activity) do
    [
      {gettext("Sales invoice created"), activity.sales},
      {gettext("Manual cost invoice import (without KSeF)"), activity.costs},
      {gettext("Working time session started"), activity.sessions}
    ]
  end

  defp paid_feature_rows(activity) do
    [
      {gettext("Leave requests"), activity.leave_requests},
      {gettext("Business trips"), activity.delegations},
      {gettext("Employment contracts"), activity.employment_contracts},
      {gettext("AI assistant connections (ChatGPT, MCP)"), activity.assistant_connections}
    ]
  end

  defp last_sign_in_text(nil), do: gettext("Last sign-in: none recorded.")

  defp last_sign_in_text(user) do
    gettext("Last sign-in: %{datetime} · %{user}",
      datetime: format_activity_datetime(user.last_signed_in_at),
      user: owner_display_name(user)
    )
  end

  defp format_activity_datetime(nil), do: gettext("none")
  defp format_activity_datetime(datetime), do: Calendar.strftime(datetime, "%d.%m.%Y %H:%M UTC")

  attr :selected_org, :map, required: true
  attr :delete_org_id, :string, default: nil

  def deletion_panel(assigns) do
    ~H"""
    <section
      id="organization-deletion"
      class="rounded-lg border border-brick-200 bg-white p-6 shadow-card"
    >
      <h2 class="text-lg/tight font-medium text-grey-900">
        {gettext("Organization deletion")}
      </h2>
      <p class="mt-2 text-sm/snug text-grey-700">
        {gettext(
          "Deleting the organization and its data from the database is permanent. User accounts are kept and detached from the organization. Data in external services is cleaned up immediately; if that fails, it may require manual intervention, and full data deletion happens within 30 days."
        )}
      </p>

      <%= if @delete_org_id == @selected_org.id do %>
        <.form
          :let={form}
          for={to_form(%{}, as: :deletion)}
          id="organization-deletion-form"
          phx-submit="delete-organization"
          class="mt-5 space-y-4"
        >
          <.input
            field={form[:name]}
            type="text"
            label={gettext("Type the exact organization name: %{name}", name: @selected_org.name)}
            autocomplete="off"
            required
          />
          <.input
            field={form[:testowa_lub_porzucona]}
            type="checkbox"
            label={gettext("I confirm that the organization is a test or abandoned one")}
          />
          <div class="flex flex-wrap gap-3">
            <FirmowidUI.Components.Button.button
              type="submit"
              variant="destructive"
              size="small"
            >
              {gettext("Delete organization permanently")}
            </FirmowidUI.Components.Button.button>
            <FirmowidUI.Components.Button.button
              type="button"
              variant="outline"
              size="small"
              phx-click="cancel-delete-organization"
            >
              {gettext("Cancel")}
            </FirmowidUI.Components.Button.button>
          </div>
        </.form>
      <% else %>
        <FirmowidUI.Components.Button.button
          type="button"
          variant="destructive"
          size="small"
          phx-click="open-delete-organization"
          class="mt-4"
        >
          {gettext("Delete organization")}
        </FirmowidUI.Components.Button.button>
      <% end %>
    </section>
    """
  end

  attr :selected_month, :any, required: true
  attr :status, :map, required: true
  attr :worksheet, :map, required: true

  def worksheet_panel(assigns) do
    ~H"""
    <section class="rounded-lg bg-white p-6 shadow-card">
      <div class="space-y-1">
        <h2 class="text-lg/tight font-medium text-grey-900">
          {gettext("Settlement worksheet")}
        </h2>
        <p class="text-sm/snug text-grey-700">{worksheet_intro(@selected_month, @status)}</p>
      </div>

      <div class="mt-8 grid gap-10 xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)]">
        <div class="space-y-8">
          <div class="space-y-4">
            <h3 class="text-base/tight font-medium text-grey-900">{gettext("Plan")}</h3>

            <div class="divide-y divide-grey-200">
              <div class="flex items-center justify-between gap-4 py-3 text-sm/snug">
                <span class="text-grey-700">{gettext("Plan for the selected month")}</span>
                <span class="font-medium text-black">{@worksheet.selected_plan_label}</span>
              </div>

              <div class="flex items-center justify-between gap-4 py-3 text-sm/snug">
                <span class="text-grey-700">{gettext("Monthly fee (net)")}</span>
                <span class="font-medium text-black">{@worksheet.monthly_price_text}</span>
              </div>
            </div>
          </div>

          <div class="space-y-4">
            <h3 class="text-base/tight font-medium text-grey-900">
              {gettext("Plan that fits the usage")}
            </h3>

            <div class="divide-y divide-grey-200">
              <div class="flex items-center justify-between gap-4 py-3 text-sm/snug">
                <span class={fitting_plan_styles(@worksheet)}>{@worksheet.fitting_plan_label}</span>
                <span class="font-medium text-black">{@worksheet.fitting_plan_price_text}</span>
              </div>
            </div>

            <p :if={@worksheet.over_limit?} class="text-sm/snug text-grey-700">
              {gettext("The usage is above the limits of the assigned plan.")}
            </p>
          </div>
        </div>

        <div class="space-y-4">
          <h3 class="text-base/tight font-medium text-grey-900">{gettext("Usage counters")}</h3>
          <div class="rounded-lg bg-grey-50 p-4">
            <div class="divide-y divide-grey-200">
              <div :for={row <- @worksheet.usage_rows} class="space-y-2 py-4 first:pt-0 last:pb-0">
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
                  <div class={counter_bar_fill_styles(row)} style={"width: #{row.bar_width}%"}></div>
                </div>

                <div class="flex items-center justify-between gap-4 text-xs/snug text-grey-700">
                  <span>{gettext("Included in the price: %{units}", units: row.limit_text)}</span>
                  <span :if={row.usage_text}>{row.usage_text}</span>
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
    <section class="rounded-lg bg-white p-6 text-sm/snug text-grey-700 shadow-card">
      {gettext("No organizations to settle.")}
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

  defp billing_status_badge_label(:trial), do: gettext("trial period")

  defp billing_status_badge_styles(:trial) do
    "inline-flex items-center rounded-full bg-rust-100 px-3 py-1 text-sm/tight text-rust-700"
  end

  defp status_chip_label(%{kind: :live_preview}), do: gettext("Live")
  defp status_chip_label(%{kind: :snapshot}), do: gettext("Historical snapshot")

  defp status_chip_styles(%{kind: :live_preview}) do
    "inline-flex items-center rounded-full px-3 py-1 text-sm/snug font-medium bg-grey-200 text-grey-900 text-center"
  end

  defp status_chip_styles(%{kind: :snapshot}) do
    "inline-flex items-center rounded-full px-3 py-1 text-sm/snug font-medium bg-rust-100 text-rust-700 text-center"
  end

  defp status_description(%{kind: :live_preview}) do
    gettext(
      "This is an indicative preview of the current month. The final settlement is based solely on the recorded snapshot."
    )
  end

  defp status_description(%{kind: :snapshot}), do: gettext("The data comes from the recorded snapshot.")

  defp worksheet_intro(selected_month, %{kind: :live_preview}) do
    gettext(
      "%{month} • an indicative preview calculated with the same billing month logic from which the snapshot is created.",
      month: format_month(selected_month)
    )
  end

  defp worksheet_intro(selected_month, %{kind: :snapshot}) do
    gettext("%{month} • the data comes from the recorded snapshot.",
      month: format_month(selected_month)
    )
  end

  defp format_month(%Date{} = month), do: Calendar.strftime(month, "%m.%Y")
  defp format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%d.%m.%Y %H:%M")

  defp fitting_plan_styles(%{over_limit?: true}), do: "font-medium text-rust-700"
  defp fitting_plan_styles(_worksheet), do: "font-medium text-black"

  defp counter_bar_fill_styles(%{over_limit: over_limit}) when over_limit > 0, do: "h-full rounded-full bg-rust-500"

  defp counter_bar_fill_styles(_row), do: "h-full rounded-full bg-teal-700"

  defp owner_display_name(%{member: %{name: name}}) when is_binary(name) and name != "", do: name
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
