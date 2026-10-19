defmodule FirmowidWeb.Landing.Components.Pricing do
  @moduledoc """
  Marketing offer cards and shared desktop/mobile plan comparison.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.Landing.Components.Primitives, only: [landing_button: 1]

  alias Phoenix.LiveView.Rendered

  @plans [
    %{
      key: "no_plan",
      name: gettext_noop("Free"),
      monthly: 0,
      yearly: 0,
      free_detail: gettext_noop("No card, no trial period"),
      audience: gettext_noop("For everyone who issues invoices in KSeF"),
      cta: gettext_noop("Create a free account")
    },
    %{
      key: "przedsiebiorca",
      name: gettext_noop("Entrepreneur"),
      monthly: 29,
      yearly: 23,
      free_detail: gettext_noop("Monthly, no commitment"),
      yearly_detail: gettext_noop("PLN 276 per year (save PLN 72)"),
      audience: gettext_noop("For sole traders with several accounts and small teams"),
      cta: gettext_noop("Try for free")
    },
    %{
      key: "firma",
      name: gettext_noop("Company"),
      monthly: 149,
      yearly: 119,
      free_detail: gettext_noop("Monthly, no commitment"),
      yearly_detail: gettext_noop("PLN 1,428 per year (save PLN 360)"),
      audience: gettext_noop("For service companies with 6–20 people"),
      cta: gettext_noop("Try for free")
    }
  ]

  @rows [
    {gettext_noop("Users"), ["2", "5", gettext_noop("unlimited")]},
    {gettext_noop("Bank accounts with transfer matching"), ["1", "3", gettext_noop("unlimited")]},
    {gettext_noop("Time tracking"),
     [gettext_noop("up to 3 projects"), gettext_noop("unlimited"), gettext_noop("unlimited")]},
    {gettext_noop("Leave requests with approval"), ["—", "✓", "✓"]},
    {gettext_noop("Firmowid in ChatGPT (panel beside the conversation)"), ["—", "✓", "✓"]}
  ]

  @doc """
  Renders offer cards, billing-period controls and the comparison.
  """
  @spec pricing_section(map()) :: Rendered.t()
  attr :billing_period, :string, required: true

  def pricing_section(assigns) do
    yearly? = assigns.billing_period == "yearly"

    assigns =
      assigns
      |> assign(:plans, localize_plans(@plans, yearly?))
      |> assign(:rows, localize_rows(@rows))
      |> assign(:yearly?, yearly?)

    ~H"""
    <section id="cennik" class="bg-white py-18 lg:py-26">
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="landing-section-intro mx-auto max-w-180 text-center lg:max-w-225 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:mt-6 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5/6.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-darkGrey lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:max-w-147 lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5 [&_h2]:text-[2.25rem] [&_h2]:leading-[1.1] [&_h2]:font-bold [&_h2]:tracking-[-0.03em] lg:[&_h2]:text-[3rem] lg:[&_h2]:leading-[1.04] lg:[&.text-center]:mx-auto lg:[&.text-center_>_p:not(.landing-eyebrow)]:mx-auto">
          <p class="landing-eyebrow mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("Pricing")}
          </p>
          <h2>{gettext("Fair pricing. No fine print.")}</h2>
          <p>
            {gettext(
              "Pay only for what you actually use. Choose the plan and billing cycle that suit you best."
            )}
          </p>
        </div>

        <div
          class="landing-billing-period mx-auto mt-9 mb-12 flex w-max max-w-full gap-1 rounded-full bg-(--landing-beige) p-1.5 [&_button]:min-h-10.5 [&_button]:min-w-29.25 [&_button]:cursor-pointer [&_button]:rounded-full [&_button]:px-5 [&_button]:py-2.5 [&_button]:text-sm/5.5 [&_button_span]:text-(--landing-accent)"
          role="group"
          aria-label={gettext("Billing period")}
        >
          <button
            type="button"
            phx-click="set_billing_period"
            phx-value-period="monthly"
            aria-pressed={to_string(not @yearly?)}
            class="relative isolate text-grey-700 transition-colors duration-200 before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:-z-10 before:h-[44px] before:w-[119px] before:-translate-1/2 before:bg-[url('/images/landing/frames/billing-active.svg')] before:bg-auto before:bg-center before:bg-no-repeat before:opacity-0 before:transition-opacity before:duration-200 hover:text-orange-700 aria-pressed:bg-white aria-pressed:text-black aria-pressed:before:opacity-100"
          >
            {pgettext("billing period", "Monthly")}
          </button>
          <button
            type="button"
            phx-click="set_billing_period"
            phx-value-period="yearly"
            aria-pressed={to_string(@yearly?)}
            class="relative isolate text-grey-700 transition-colors duration-200 before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:-z-10 before:h-[44px] before:w-[132px] before:-translate-1/2 before:bg-[url('/images/landing/frames/billing-yearly-active.svg')] before:bg-auto before:bg-center before:bg-no-repeat before:opacity-0 before:transition-opacity before:duration-200 hover:text-orange-700 aria-pressed:bg-white aria-pressed:text-black aria-pressed:before:opacity-100"
          >
            {pgettext("billing period", "Yearly")}
            <span>−20%</span>
          </button>
        </div>

        <div
          id="landing-pricing"
          phx-hook="LandingPricing"
          class="grid gap-6 lg:grid-cols-[1.45fr_repeat(3,minmax(0,1fr))] lg:gap-0"
        >
          <article
            :for={plan <- @plans}
            class={[
              "landing-pricing-card relative flex flex-col rounded-2xl bg-(--landing-beige) px-6 py-7 [&_.landing-button]:mt-10 [&_.landing-button]:text-base lg:[&_.landing-button]:mt-8 lg:[&.landing-pricing-featured]:rounded-b-none",
              plan.featured &&
                "landing-pricing-featured text-[#f5f1ea] [&_.landing-pricing-audience]:text-grey-300 [&_.landing-pricing-detail]:text-orange-500-landing [&_.landing-pricing-name]:text-orange-500-landing [&_.landing-pricing-price_>_span]:text-grey-300 [&.landing-pricing-featured]:bg-grey-900"
            ]}
          >
            <p
              :if={plan.featured}
              class="absolute -top-2.5 left-1/2 w-max -translate-x-1/2 rounded-full bg-orange-500-landing px-2 py-0.5 text-[10px] font-medium text-[#0f0f0f]"
            >
              {gettext("Most popular")}
            </p>
            <p class="landing-pricing-name mb-4.5 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
              {plan.name}
            </p>
            <p class="landing-pricing-price mt-0 flex flex-wrap items-baseline gap-2 [&_>_span]:text-sm [&_>_span]:text-darkGrey [&_strong]:text-3xl [&_strong]:leading-none [&_strong]:font-bold [&_strong]:tracking-[-0.04em] lg:[&_strong]:text-3xl">
              <strong
                id={"pricing-price-#{plan.key}"}
                class="t-digit-group"
                data-value={plan.price_label}
                phx-hook="NumberPopIn"
                aria-hidden="true"
              >
                <span
                  :for={{digit, index} <- Enum.with_index(String.graphemes(plan.price_label))}
                  class="t-digit"
                  style={"--digit-stagger-index: #{index};"}
                >
                  {digit}
                </span>
              </strong>
              <span class="sr-only">{plan.price_label}</span>
              <span>{if plan.free?, do: gettext("forever"), else: gettext("/ month net")}</span>
            </p>
            <p class="landing-pricing-detail mt-5 mb-3 text-xs/normal text-(--landing-accent)">
              {plan.detail}
            </p>
            <p class="landing-pricing-audience text-sm/5.25 text-darkGrey lg:min-h-11.5">
              {plan.audience}
            </p>
            <.landing_button
              navigate={~p"/zarejestruj"}
              variant={if plan.featured, do: :orange, else: :outline}
              class={["whitespace-nowrap", plan.featured && "lg:px-3"]}
              data-landing-cta="pricing_register"
              data-landing-plan={plan.key}
              data-landing-billing-period={@billing_period}
            >
              {plan.cta}
            </.landing_button>
          </article>

          <div class="lg:col-1 lg:row-1 lg:self-end lg:pb-8 [&_h3]:mb-2 [&_h3]:text-lg [&_h3]:font-semibold [&_p]:text-sm [&_p]:text-darkGrey">
            <h3>{gettext("Compare plans")}</h3>
            <p>
              {if @yearly?,
                do: gettext("Net prices with annual billing (−20%)."),
                else: gettext("Net prices. Save 20% with annual billing.")}
            </p>
          </div>

          <div class="landing-pricing-plans sticky top-(--landing-nav-height) z-20 grid grid-cols-3 rounded-md bg-(--landing-beige) *:px-1.5 *:py-3 *:text-center *:text-xs *:font-semibold lg:col-[2/5] lg:row-2 lg:rounded-t-2xl lg:rounded-b-none lg:*:flex lg:*:min-h-17 lg:*:flex-col lg:*:justify-center lg:*:bg-white lg:*:py-2.5 lg:*:text-sm lg:*:text-transparent [&_.landing-pricing-featured]:bg-transparent [&_.landing-pricing-featured]:text-(--landing-accent) lg:[&_.landing-pricing-featured]:bg-grey-900 lg:[&_.landing-pricing-featured]:text-transparent [&_small]:hidden lg:[&.is-stuck_>_*]:bg-(--landing-beige) lg:[&.is-stuck_>_*]:text-[#0f0f0f] lg:[&.is-stuck_>_.landing-pricing-featured]:bg-grey-900 lg:[&.is-stuck_>_.landing-pricing-featured]:text-white lg:[&.is-stuck_small]:mt-1 lg:[&.is-stuck_small]:block">
            <span
              :for={plan <- @plans}
              class={[plan.featured && "landing-pricing-featured"]}
            >
              {plan.name}<small>{pgettext("landing card price", "%{amount} PLN", amount: plan.price)}</small>
            </span>
          </div>

          <p class="text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase lg:col-1 lg:row-2 lg:self-end lg:pb-7">
            {gettext("Key differences")}
          </p>

          <dl class="lg:col-[1/5] lg:row-3">
            <div
              :for={{label, values} <- @rows}
              class="grid grid-cols-3 border-b border-(--landing-line) text-xs lg:grid-cols-[1.45fr_repeat(3,minmax(0,1fr))] lg:text-sm [&_dd]:px-1 [&_dd]:pt-2 [&_dd]:pb-4.5 [&_dd]:text-center [&_dd]:font-semibold [&_dd]:text-[#0f0f0f] lg:[&_dd]:px-3 lg:[&_dd]:py-4 [&_dd.landing-pricing-featured]:bg-transparent [&_dd.landing-pricing-featured]:text-[#0f0f0f] lg:[&_dd.landing-pricing-featured]:bg-grey-900 lg:[&_dd.landing-pricing-featured]:text-[#f5f1ea] lg:[&_dd.landing-pricing-featured[data-tick]]:text-orange-500-landing [&_dd[data-tick]]:text-lg [&_dd[data-tick]]:text-(--landing-accent) [&_dt]:col-span-full [&_dt]:pt-4.5 [&_dt]:pb-2 [&_dt]:font-normal lg:[&_dt]:col-auto lg:[&_dt]:py-4 lg:[&_dt]:pr-6"
            >
              <dt>{label}</dt>
              <dd
                :for={{value, index} <- Enum.with_index(values)}
                class={[index == 1 && "landing-pricing-featured"]}
                data-tick={value == "✓"}
              >
                <span class="sr-only">{Enum.at(@plans, index).name}: </span>
                <img
                  :if={value == "✓"}
                  src={~p"/images/landing/icons/check.svg"}
                  alt=""
                  width="12"
                  height="13"
                  class="mx-auto inline-block"
                />
                <span :if={value != "✓"} aria-hidden={if value == "—", do: "true"}>{value}</span>
                <span :if={value in ["✓", "—"]} class="sr-only">
                  {if value == "✓", do: gettext("Included"), else: gettext("Not included")}
                </span>
              </dd>
            </div>
          </dl>
        </div>

        <button
          type="button"
          class="before:mask-size-auto relative isolate mx-auto mt-8 block min-h-10.25 w-64.5 max-w-full cursor-pointer rounded-full bg-orange-700 px-4 py-2.5 text-sm text-white transition-colors duration-200 before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:-z-10 before:h-[43px] before:w-[260px] before:-translate-1/2 before:bg-orange-700 before:mask-[url('/images/landing/frames/comparison.svg')] before:mask-center before:mask-no-repeat before:transition-colors before:duration-200 hover:bg-orange-500 hover:before:bg-orange-500 focus-visible:outline-2 focus-visible:outline-offset-4"
        >
          {ngettext("Show %{count} feature", "Show all %{count} features", 20)}
        </button>

        <p class="mt-10 text-center text-base font-medium">
          {gettext("Paid features free until the end of next month. No card required.")}
        </p>
      </div>
    </section>
    """
  end

  defp localize_plans(plans, yearly?) do
    Enum.map(plans, fn plan ->
      free? = plan.monthly == 0
      price = to_string(if yearly?, do: plan.yearly, else: plan.monthly)

      detail =
        cond do
          free? -> plan.free_detail
          yearly? -> plan.yearly_detail
          true -> plan.free_detail
        end

      %{
        key: plan.key,
        name: Gettext.gettext(Firmowid.Gettext, plan.name),
        audience: Gettext.gettext(Firmowid.Gettext, plan.audience),
        cta: Gettext.gettext(Firmowid.Gettext, plan.cta),
        featured: plan.key == "przedsiebiorca",
        free?: free?,
        price: price,
        price_label: pgettext("landing card price", "%{amount} PLN", amount: price),
        detail: Gettext.gettext(Firmowid.Gettext, detail)
      }
    end)
  end

  defp localize_rows(rows) do
    Enum.map(rows, fn {label, values} ->
      {Gettext.gettext(Firmowid.Gettext, label), Enum.map(values, &Gettext.gettext(Firmowid.Gettext, &1))}
    end)
  end
end
