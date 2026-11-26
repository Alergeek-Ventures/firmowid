defmodule FirmowidWeb.Settings.Components.SubscriptionTab do
  @moduledoc """
  Function component for the owner-only subscription tab.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.Tabs, only: [segmented_control: 1]

  alias Firmowid.Billing.PlanCatalog
  alias FirmowidWeb.Billing.Utilities.PlanOffer
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Settings.Components.Helpers

  @doc """
  Renders the owner-only subscription tab.
  """
  @spec subscription_tab(map()) :: Phoenix.LiveView.Rendered.t()
  attr :worksheet, :any, required: true

  attr :ocr_documents_row, :any,
    default: nil,
    doc: "the month's documents sent to OCR, as a usage row"

  attr :subscription, :any, default: nil, doc: "the subscription as Stripe reports it, if any"
  attr :plan_granted?, :boolean, default: false

  attr :purchase, :map,
    default: nil,
    doc:
      "what a purchase would be (billing_period, free_trial?) and the quotas the plans differ in, if the company can buy a plan"

  def subscription_tab(assigns) do
    ~H"""
    <%= if @worksheet do %>
      <div class="grid w-full gap-8">
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

            <%!-- A paid subscription shows the price Stripe charges, which may be yearly. --%>
            <Helpers.settings_display_field :if={@subscription} label={gettext("Fee (net)")}>
              {Worksheet.net_price_text(net_price(@subscription), @subscription.billing_period)}
            </Helpers.settings_display_field>

            <Helpers.settings_display_field :if={!@subscription} label={gettext("Monthly fee (net)")}>
              {@worksheet.monthly_price_text}
            </Helpers.settings_display_field>
          </div>

          <.funding
            subscription={@subscription}
            plan_granted?={@plan_granted?}
          />

          <div class="space-y-3 rounded-lg bg-grey-50 p-4">
            <h3 class="text-sm/none font-medium text-grey-900">
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
            class="rounded-lg bg-grey-50 p-4 text-sm/[1.35] text-grey-700"
          >
            {gettext("Your current usage is within the plan limits.")}
          </div>
        </section>

        <section :if={@purchase} id="subscription-plans" class="space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-base leading-none font-semibold text-grey-900">
              {gettext("Compare plans")}
            </h2>

            <.segmented_control label={gettext("Billing period")}>
              <:option
                :for={period <- PlanCatalog.billing_periods()}
                active={period == @purchase.billing_period}
                phx-click="purchase-period"
                value={Atom.to_string(period)}
              >
                {Worksheet.period_label(period)}
              </:option>
            </.segmented_control>
          </div>

          <%!-- The cards share the rows of one grid, so each quota and the button sit on one line across the plans. --%>
          <div class="grid gap-x-5 lg:grid-cols-3">
            <article
              :for={{plan, index} <- Enum.with_index(PlanOffer.plans())}
              id={"subscription-plan-#{plan}"}
              class={[
                "grid grid-rows-subgrid rounded-2xl border bg-white p-5 max-lg:not-last:mb-4",
                if(plan == @worksheet.selected_plan, do: "border-grey-900", else: "border-grey-300")
              ]}
              style={"grid-row: span #{length(@purchase.quotas) + 3}"}
            >
              <div>
                <div class="flex min-h-7 flex-wrap items-center justify-between gap-2">
                  <h3 class="text-base leading-none font-semibold text-grey-900">
                    {Worksheet.plan_label(plan)}
                  </h3>
                  <span :if={plan == @worksheet.selected_plan} class={plan_badge_styles(plan)}>
                    {plan_badge_label(plan)}
                  </span>
                </div>

                <p class="mt-3 text-2xl/none font-semibold tracking-tight text-grey-900 tabular-nums">
                  {price_text(plan, @purchase.billing_period)}
                </p>
              </div>

              <dl
                class="mt-4 grid grid-rows-subgrid text-sm/snug"
                style={"grid-row: span #{length(@purchase.quotas)}"}
              >
                <div
                  :for={{label, values} <- @purchase.quotas}
                  class="flex items-baseline justify-between gap-4 border-grey-200 py-2 not-first:border-t"
                >
                  <dt class="min-w-0 text-grey-700">{label}</dt>
                  <dd class="shrink-0 text-right font-semibold text-grey-900">
                    {Enum.at(values, index)}
                  </dd>
                </div>
              </dl>

              <%!-- The Free plan is the one the company has; only what a paid plan adds is listed. --%>
              <div>
                <div :if={plan in PlanCatalog.paid_plans()} class="border-t border-grey-200 pt-4">
                  <p class="text-sm font-medium text-grey-900">{added_heading(plan)}</p>
                  <ul class="mt-2 space-y-1.5 text-sm/snug text-grey-700">
                    <li :for={{label, _value} <- PlanOffer.added(plan)} class="flex gap-2">
                      <.icon name="hero-check-mini" class="mt-0.5 size-4 shrink-0 text-grey-900" />
                      <span>{label}</span>
                    </li>
                  </ul>
                </div>
              </div>

              <div class="self-end pt-5">
                <.button
                  :if={plan in PlanCatalog.paid_plans()}
                  id={"subscription-buy-#{plan}"}
                  type="button"
                  variant={buy_button_variant(plan)}
                  class="w-full"
                  phx-click="purchase"
                  phx-value-plan={plan}
                  phx-disable-with={gettext("Opening the payment page...")}
                >
                  {gettext("Buy the %{plan} plan", plan: Worksheet.plan_label(plan))}
                </.button>
              </div>
            </article>
          </div>

          <p class="text-sm text-grey-600">
            {if @purchase.free_trial?,
              do: gettext("Next you enter the card on Stripe's page. Nothing is charged today."),
              else: gettext("Next you pay with a card on Stripe's page.")}
          </p>
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
              <%= for row <- @worksheet.usage_rows ++ List.wrap(@ocr_documents_row) do %>
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
      <div class="rounded-lg bg-grey-50 p-4 text-sm/[1.35] text-grey-700">
        {gettext("This preview is available only to the organization owner.")}
      </div>
    <% end %>
    """
  end

  # Who pays for the plan; the first clause that matches wins: a subscription, a plan granted by
  # hand. A free plan shows nothing.
  attr :subscription, :any, required: true
  attr :plan_granted?, :boolean, required: true

  defp funding(%{subscription: %{}} = assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class={["text-sm/snug", payment_line_styles(@subscription)]}>
        {payment_line(@subscription)}
      </p>
      <.button
        id="subscription-manage-payments"
        type="button"
        variant="outline"
        size="small"
        phx-click="manage-payments"
        phx-disable-with={gettext("Opening the payment page...")}
      >
        {gettext("Manage subscription")}
      </.button>
    </div>
    """
  end

  defp funding(%{plan_granted?: true} = assigns) do
    ~H"""
    <p class="text-sm/snug text-grey-700">
      {gettext("This plan is granted to your organization. Nothing is charged for it.")}
    </p>
    """
  end

  defp funding(assigns), do: ~H""

  # What the subscription does next, as Stripe last reported it. Stripe charges the price of the
  # plan; prorations show in its portal.
  defp payment_line(%{trialing?: true, cancel_at_period_end: true} = subscription) do
    gettext("Trial of the %{plan} plan until %{date}. Nothing is charged.",
      plan: Worksheet.plan_label(subscription.plan),
      # Stripe ends the trial at the start of the day after its last one.
      date: format_date(Date.add(subscription.current_period_end, -1))
    )
  end

  defp payment_line(%{payment_overdue?: true}) do
    gettext(
      "The last payment did not go through. Stripe will try again, and if that fails, the company returns to the Free plan. Change the card in “Manage subscription”."
    )
  end

  defp payment_line(%{cancel_at_period_end: true} = subscription) do
    gettext(
      "The plan stays on until %{date}, then the company returns to the Free plan. You can undo the cancellation in “Manage subscription”.",
      date: format_date(subscription.current_period_end)
    )
  end

  defp payment_line(%{trialing?: true} = subscription) do
    gettext("Trial until %{date}. First payment: %{amount} gross · %{period}",
      date: format_date(subscription.current_period_end),
      amount: gross_price(subscription),
      period: Worksheet.period_label(subscription.billing_period)
    )
  end

  defp payment_line(subscription) do
    Enum.join(
      [
        gettext("Next payment on %{date}: %{amount} gross",
          date: format_date(subscription.current_period_end),
          amount: gross_price(subscription)
        ),
        Worksheet.period_label(subscription.billing_period)
      ],
      " · "
    )
  end

  defp payment_line_styles(%{payment_overdue?: true}), do: "text-rust-700"
  defp payment_line_styles(_subscription), do: "text-grey-700"

  # A paid plan lists what it adds to the plan below it.
  defp added_heading(plan) do
    cheaper = PlanOffer.plans() |> Enum.take_while(&(&1 != plan)) |> List.last()

    gettext("Everything in the %{plan} plan, and:", plan: Worksheet.plan_label(cheaper))
  end

  # The plan most companies outgrow the Free one into stands out, as on the pricing page.
  defp buy_button_variant(:przedsiebiorca), do: "special"
  defp buy_button_variant(_plan), do: "outline"

  defp price_text(:free, _billing_period), do: Worksheet.format_money(Decimal.new(0))

  defp price_text(plan, billing_period),
    do: Worksheet.net_price_text(PlanCatalog.net_price_pln(plan, billing_period), billing_period)

  defp gross_price(subscription), do: Worksheet.format_money(subscription.amount)

  defp net_price(subscription), do: subscription.amount |> PlanCatalog.without_vat() |> Decimal.round(2)

  defp format_date(date), do: Firmowid.Cldr.Date.to_string!(date, format: :long)

  defp plan_badge_label(:no_plan), do: gettext("no plan")
  defp plan_badge_label(_plan), do: gettext("active")

  defp plan_badge_styles(:no_plan), do: "rounded-full bg-grey-200 px-3 py-1 text-sm/tight text-grey-700"

  defp plan_badge_styles(_plan) do
    "rounded-full bg-rust-100 px-3 py-1 text-sm/tight text-rust-700"
  end

  defp counter_bar_fill_styles(%{over_limit: over_limit}) when over_limit > 0, do: "h-full rounded-full bg-rust-500"

  defp counter_bar_fill_styles(_row), do: "h-full rounded-full bg-teal-700"
end
