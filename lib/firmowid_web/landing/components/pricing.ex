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
    {gettext_noop("Users"), [gettext_noop("2"), gettext_noop("5"), gettext_noop("unlimited")]},
    {gettext_noop("Bank accounts with transfer matching"),
     [gettext_noop("1"), gettext_noop("3"), gettext_noop("unlimited")]},
    {gettext_noop("Time tracking"),
     [gettext_noop("up to 3 projects"), gettext_noop("unlimited"), gettext_noop("unlimited")]},
    {gettext_noop("Leave requests with approval"), [false, true, true]},
    {gettext_noop("Firmowid in ChatGPT (panel beside the conversation)"), [false, true, true]}
  ]

  @sections [
    {gettext_noop("Invoices and KSeF"),
     [
       {gettext_noop("Sales invoices"),
        [gettext_noop("unlimited"), gettext_noop("unlimited"), gettext_noop("unlimited")]},
       {gettext_noop("KSeF: sending invoices and downloading purchases"),
        [gettext_noop("unlimited"), gettext_noop("unlimited"), gettext_noop("unlimited")]},
       {gettext_noop("Clear invoice wizard"), [true, true, true]},
       {gettext_noop("Customer database with cooperation statistics"), [true, true, true]},
       {gettext_noop("Invoices in 33 currencies"), [true, true, true]},
       {gettext_noop("Reverse charge for EU customers (automatic)"), [true, true, true]},
       {gettext_noop("ZIP package for your accountant"), [true, true, true]},
       {gettext_noop("Document OCR"),
        [
          gettext_noop("10 credits / month"),
          gettext_noop("50 credits / month"),
          gettext_noop("unlimited")
        ]}
     ]},
    {gettext_noop("Banking and payments"), [{gettext_noop("Email notifications"), [false, true, true]}]},
    {gettext_noop("Team and working time"),
     [
       {gettext_noop("Project cost"), [true, true, true]},
       {gettext_noop("Employee and project management"), [false, true, true]},
       {gettext_noop("PDF time tracking and payroll report"), [false, false, true]}
     ]},
    {gettext_noop("HR"),
     [
       {gettext_noop("Employee contracts and documents"), [false, true, true]},
       {gettext_noop("Business trips"), [false, false, true]}
     ]},
    {gettext_noop("ChatGPT and integrations"), [{gettext_noop("MCP (Claude, Cursor and others)"), [false, true, true]}]},
    {gettext_noop("Data and security"), [{gettext_noop("Self-host, open source (AGPL-3.0)"), [true, true, true]}]},
    {gettext_noop("Trial period"),
     [
       {gettext_noop("Paid features for free"),
        [
          false,
          gettext_noop("until the end of next month"),
          gettext_noop("until the end of next month")
        ]}
     ]}
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
      |> assign(
        :sections,
        Enum.map(@sections, fn {title, rows} ->
          {Gettext.gettext(Firmowid.Gettext, title), localize_rows(rows)}
        end)
      )
      |> assign(:yearly?, yearly?)

    ~H"""
    <section
      id="cennik"
      class="bg-white py-18 lg:py-26 max-lg:[&_dd]:text-[13px] max-lg:[&_dt]:text-sm"
    >
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="mx-auto max-w-180 text-center lg:max-w-225">
          <p class="mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("Pricing")}
          </p>
          <h2 class="lg:text-5xl text-[38px] leading-[1.1] font-bold tracking-[-0.03em] lg:leading-[1.04]">
            {gettext("Fair pricing. No fine print.")}
          </h2>
          <p class="mx-auto mt-6 text-h5/6.75 text-grey-700 lg:max-w-147 lg:text-h5">
            {gettext(
              "Pay only for what you actually use. Choose the plan and billing cycle that suit you best."
            )}
          </p>
        </div>

        <div
          class="mx-auto mt-9 mb-6 flex w-max max-w-full gap-1 rounded-full bg-(--landing-beige) p-1.5 lg:mb-12 [&_button]:min-h-10.5 [&_button]:min-w-29.25 [&_button]:cursor-pointer [&_button]:rounded-full [&_button]:px-5 [&_button]:py-2.5 [&_button]:text-sm/5.5 [&_button_span]:text-(--landing-accent)"
          role="group"
          aria-label={gettext("Billing period")}
        >
          <button
            type="button"
            phx-click="set_billing_period"
            phx-value-period="monthly"
            aria-pressed={to_string(not @yearly?)}
            class="relative isolate text-grey-700 transition-colors duration-300 before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:-z-10 before:h-[44px] before:w-[119px] before:-translate-1/2 before:bg-[url('/images/landing/frames/billing-active.svg')] before:bg-auto before:bg-center before:bg-no-repeat before:opacity-0 before:transition-opacity before:duration-300 hover:text-rust-700 aria-pressed:bg-white aria-pressed:text-black aria-pressed:before:opacity-100"
          >
            {pgettext("billing period", "Monthly")}
          </button>
          <button
            type="button"
            phx-click="set_billing_period"
            phx-value-period="yearly"
            aria-pressed={to_string(@yearly?)}
            class="relative isolate text-grey-700 transition-colors duration-300 before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:-z-10 before:h-[44px] before:w-[132px] before:-translate-1/2 before:bg-[url('/images/landing/frames/billing-yearly-active.svg')] before:bg-auto before:bg-center before:bg-no-repeat before:opacity-0 before:transition-opacity before:duration-300 hover:text-rust-700 aria-pressed:bg-white aria-pressed:text-black aria-pressed:before:opacity-100"
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
            data-pricing-card
            class={[
              "relative flex flex-col rounded-2xl px-6 py-7",
              if(plan.featured,
                do: "rounded-b-none bg-grey-900 text-[#f5f1ea]",
                else: "bg-(--landing-beige)"
              )
            ]}
          >
            <p
              :if={plan.featured}
              class="absolute -top-2.5 left-1/2 w-max -translate-x-1/2 rounded-full bg-rust-500 px-2 py-0.5 text-[10px] font-medium text-[#0f0f0f]"
            >
              {gettext("Most popular")}
            </p>
            <p class={[
              "mb-4.5 text-xs font-bold tracking-[0.08em] uppercase",
              if(plan.featured, do: "text-rust-500", else: "text-(--landing-accent)")
            ]}>
              {plan.name}
            </p>
            <p class={[
              "mt-0 flex flex-wrap items-baseline gap-2 [&_>_span]:text-sm [&_strong]:text-3xl [&_strong]:leading-none [&_strong]:font-bold [&_strong]:tracking-[-0.04em] lg:[&_strong]:text-3xl",
              if(plan.featured, do: "[&_>_span]:text-grey-300", else: "[&_>_span]:text-grey-700")
            ]}>
              <strong
                id={"pricing-price-#{plan.key}"}
                class="group/digits inline-flex items-baseline whitespace-nowrap tabular-nums"
                data-value={plan.price_label}
                phx-hook="NumberPopIn"
                aria-hidden="true"
              >
                <span
                  :for={{digit, index} <- Enum.with_index(String.graphemes(plan.price_label))}
                  class="inline-block will-change-[transform,opacity,filter] group-data-animating/digits:animate-[t-digit-pop-in_var(--digit-dur)_var(--digit-ease)_both] group-data-animating/digits:[animation-delay:calc(var(--digit-stagger)*var(--digit-stagger-index,0))] motion-reduce:animate-none!"
                  style={"--digit-stagger-index: #{index};"}
                >
                  {digit}
                </span>
              </strong>
              <span class="sr-only">{plan.price_label}</span>
              <span>{if plan.free?, do: gettext("forever"), else: gettext("/ month net")}</span>
            </p>
            <p class={[
              "mt-5 mb-3 text-xs/normal",
              if(plan.featured, do: "text-rust-500", else: "text-(--landing-accent)")
            ]}>
              {plan.detail}
            </p>
            <p class={[
              "text-sm/5.25 lg:min-h-11.5",
              if(plan.featured, do: "text-grey-300", else: "text-grey-700")
            ]}>
              {plan.audience}
            </p>
            <.landing_button
              navigate={~p"/zarejestruj"}
              variant={if plan.featured, do: :rust, else: :pricing_outline}
              class={[
                "mt-10 whitespace-nowrap max-lg:w-full max-lg:px-2 lg:mt-8",
                plan.featured && "lg:px-3"
              ]}
              data-landing-cta="pricing_register"
              data-landing-plan={plan.key}
              data-landing-billing-period={@billing_period}
            >
              {plan.cta}
            </.landing_button>
          </article>

          <div class="lg:col-1 lg:row-1 lg:self-end lg:pb-8 [&_h3]:mb-2 [&_h3]:text-lg [&_h3]:font-semibold [&_p]:text-sm [&_p]:text-grey-700">
            <h3>{gettext("Compare plans")}</h3>
            <p>
              {if @yearly?,
                do: gettext("Net prices with annual billing (−20%)."),
                else: gettext("Net prices. Save 20% with annual billing.")}
            </p>
          </div>

          <div
            id="landing-pricing-plans"
            class="group/pricing sticky top-(--landing-nav-height) z-20 grid grid-cols-3 rounded-md bg-(--landing-beige) *:px-1.5 *:py-3 *:text-center *:text-[13px] *:font-semibold lg:col-[2/5] lg:row-2 lg:rounded-t-2xl lg:rounded-b-none lg:*:flex lg:*:min-h-17 lg:*:flex-col lg:*:justify-center lg:*:py-2.5 lg:*:text-sm lg:*:transition-colors lg:*:duration-200 lg:data-[stuck=true]:overflow-hidden lg:data-[stuck=true]:rounded-2xl lg:motion-reduce:*:transition-none"
          >
            <span
              :for={plan <- @plans}
              class={[
                if(plan.featured,
                  do: "bg-transparent text-(--landing-accent) lg:bg-grey-900 lg:text-white",
                  else:
                    "lg:bg-white lg:text-[#0f0f0f] lg:group-data-[stuck=true]/pricing:bg-(--landing-beige)"
                )
              ]}
            >
              <span class="lg:opacity-0 lg:transition-opacity lg:duration-200 lg:group-data-[stuck=true]/pricing:opacity-100 lg:motion-reduce:transition-none">
                {plan.name}<small class="hidden lg:mt-1 lg:block">{pgettext(
                  "landing card price",
                  "%{amount} PLN",
                  amount: plan.price
                )}</small>
              </span>
            </span>
          </div>

          <p class="text-caps-sm font-bold tracking-[0.08em] text-rust-700 uppercase lg:col-1 lg:row-2 lg:self-end lg:pb-7">
            {gettext("Key differences")}
          </p>

          <dl class="lg:col-[1/5] lg:row-3">
            <.comparison_row
              :for={{label, values} <- @rows}
              label={label}
              values={values}
              plans={@plans}
            />
          </dl>

          <div
            id="landing-pricing-features"
            aria-hidden="true"
            inert
            data-expanded="false"
            class="-mt-6 grid grid-rows-[0fr] self-start transition-[grid-template-rows] duration-600 ease-out data-[expanded=true]:grid-rows-[1fr] motion-reduce:transition-none lg:col-span-full lg:mt-0"
          >
            <div class="min-h-0 overflow-hidden">
              <section :for={{title, rows} <- @sections}>
                <h4 class="grid grid-cols-3 lg:grid-cols-[1.45fr_repeat(3,minmax(0,1fr))]">
                  <span class="col-span-full pt-6 pb-2 text-caps-sm font-bold tracking-[0.08em] text-rust-700 uppercase lg:col-span-1 lg:py-5">{title}</span>
                  <span aria-hidden="true" class="hidden lg:col-3 lg:block lg:bg-grey-900"></span>
                </h4>
                <dl>
                  <.comparison_row
                    :for={{label, values} <- rows}
                    label={label}
                    values={values}
                    plans={@plans}
                  />
                </dl>
              </section>
            </div>
          </div>

          <div
            id="landing-pricing-tab-end"
            aria-hidden="true"
            class="hidden h-6 lg:col-span-full lg:grid lg:grid-cols-[1.45fr_repeat(3,minmax(0,1fr))]"
          >
            <span class="col-3 rounded-b-2xl bg-grey-900"></span>
          </div>

          <button
            id="landing-pricing-toggle"
            type="button"
            aria-controls="landing-pricing-features"
            aria-expanded="false"
            class="before:mask-size-auto group relative isolate mx-auto mt-2 flex min-h-10.25 w-max max-w-full min-w-64.5 cursor-pointer items-center justify-center gap-2 rounded-full bg-rust-700 px-4 py-2.5 text-sm text-white transition-colors duration-200 before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:-z-10 before:h-[43px] before:w-[260px] before:-translate-1/2 before:bg-rust-700 before:mask-[url('/images/landing/frames/comparison.svg')] before:mask-center before:mask-no-repeat before:transition-colors before:duration-200 hover:bg-rust-500 hover:before:bg-rust-500 focus-visible:outline-2 focus-visible:outline-offset-4 aria-expanded:bg-transparent aria-expanded:text-rust-700 aria-expanded:outline-none aria-expanded:before:bg-transparent aria-expanded:hover:bg-transparent aria-expanded:hover:before:bg-transparent aria-expanded:focus-visible:underline lg:col-span-full lg:mt-8"
          >
            <span class="group-aria-expanded:hidden">{ngettext(
              "Show %{count} feature",
              "Show all %{count} features",
              20
            )}</span>
            <span class="hidden group-aria-expanded:inline">{gettext("Collapse comparison")}</span>
            <svg
              aria-hidden="true"
              viewBox="0 0 16 16"
              fill="none"
              class="size-4 shrink-0 transition-transform duration-500 group-aria-expanded:rotate-180 motion-reduce:transition-none"
            >
              <path
                d="m3 6 5 5 5-5"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </button>
        </div>

        <p class="mt-10 text-center text-base font-medium">
          {gettext("Paid features free until the end of next month. No card required.")}
        </p>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :values, :list, required: true
  attr :plans, :list, required: true

  defp comparison_row(assigns) do
    ~H"""
    <div class="grid grid-cols-3 border-b border-(--landing-line) text-xs lg:grid-cols-[1.45fr_repeat(3,minmax(0,1fr))] lg:text-sm [&_dt]:col-span-full [&_dt]:pt-4.5 [&_dt]:pb-2 [&_dt]:font-normal lg:[&_dt]:col-auto lg:[&_dt]:py-4 lg:[&_dt]:pr-6">
      <dt>{@label}</dt>
      <dd
        :for={{value, index} <- Enum.with_index(@values)}
        class={[
          "px-1 pt-2 pb-4.5 text-center font-semibold text-[#0f0f0f] lg:px-3 lg:py-4",
          index == 1 && "bg-transparent lg:bg-grey-900 lg:text-[#f5f1ea]"
        ]}
      >
        <span class="sr-only">{Enum.at(@plans, index).name}: </span>
        <span
          :if={value == true}
          aria-hidden="true"
          class={[
            "mx-auto inline-block h-3.25 w-3 bg-rust-700 mask-[url('/images/landing/icons/check.svg')] mask-contain mask-center mask-no-repeat",
            index == 1 && "lg:bg-rust-500"
          ]}
        ></span>
        <span :if={value == false} aria-hidden="true" class="text-[#737373]">—</span>
        <span :if={is_boolean(value)} class="sr-only">{if value,
          do: gettext("Included"),
          else: gettext("Not included")}</span>
        <span :if={is_binary(value)}>{value}</span>
      </dd>
    </div>
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
      {Gettext.gettext(Firmowid.Gettext, label),
       Enum.map(values, fn
         value when is_boolean(value) -> value
         value -> Gettext.gettext(Firmowid.Gettext, value)
       end)}
    end)
  end
end
