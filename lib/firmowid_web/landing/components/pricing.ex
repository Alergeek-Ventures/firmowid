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
    <section id="cennik" class="landing-section bg-white">
      <div class="landing-container">
        <div class="landing-section__intro mx-auto text-center">
          <p class="landing-eyebrow">{gettext("Pricing")}</p>
          <h2>{gettext("Fair pricing. No fine print.")}</h2>
          <p>
            {gettext(
              "Pay only for what you actually use. Choose the plan and billing cycle that suit you best."
            )}
          </p>
        </div>

        <div class="landing-period" role="group" aria-label={gettext("Billing period")}>
          <button
            type="button"
            phx-click="set_billing_period"
            phx-value-period="monthly"
            aria-pressed={to_string(not @yearly?)}
          >
            {pgettext("billing period", "Monthly")}
          </button>
          <button
            type="button"
            phx-click="set_billing_period"
            phx-value-period="yearly"
            aria-pressed={to_string(@yearly?)}
          >
            {pgettext("billing period", "Yearly")}
            <span>−20%</span>
          </button>
        </div>

        <div id="landing-pricing" phx-hook="LandingPricing" class="landing-pricing">
          <article
            :for={plan <- @plans}
            class={["landing-pricing__card", plan.featured && "landing-pricing__featured"]}
          >
            <p :if={plan.featured} class="landing-pricing__popular">{gettext("Most popular")}</p>
            <p class="landing-pricing__name">{plan.name}</p>
            <p class="landing-pricing__price">
              <strong>{pgettext("landing card price", "%{amount} PLN", amount: plan.price)}</strong>
              <span>{if plan.free?, do: gettext("forever"), else: gettext("/ month net")}</span>
            </p>
            <p class="landing-pricing__detail">{plan.detail}</p>
            <p class="landing-pricing__audience">{plan.audience}</p>
            <.landing_button
              navigate={~p"/zarejestruj"}
              variant={if plan.featured, do: :orange, else: :outline}
              data-landing-cta="pricing_register"
              data-landing-plan={plan.key}
              data-landing-billing-period={@billing_period}
            >
              {plan.cta}
            </.landing_button>
          </article>

          <div class="landing-pricing__label">
            <h3>{gettext("Compare plans")}</h3>
            <p>
              {if @yearly?,
                do: gettext("Net prices with annual billing (−20%)."),
                else: gettext("Net prices. Save 20% with annual billing.")}
            </p>
          </div>

          <div class="landing-pricing__plans">
            <span :for={plan <- @plans} class={[plan.featured && "landing-pricing__featured"]}>
              {plan.name}<small>{pgettext("landing card price", "%{amount} PLN", amount: plan.price)}</small>
            </span>
          </div>

          <p class="landing-pricing__eyebrow">{gettext("Key differences")}</p>

          <dl class="landing-pricing__rows">
            <div :for={{label, values} <- @rows} class="landing-pricing__row">
              <dt>{label}</dt>
              <dd
                :for={{value, index} <- Enum.with_index(values)}
                class={[index == 1 && "landing-pricing__featured"]}
                data-tick={value == "✓"}
              >
                <span class="sr-only">{Enum.at(@plans, index).name}: </span>
                <span aria-hidden={if value in ["✓", "—"], do: "true"}>{value}</span>
                <span :if={value in ["✓", "—"]} class="sr-only">
                  {if value == "✓", do: gettext("Included"), else: gettext("Not included")}
                </span>
              </dd>
            </div>
          </dl>
        </div>

        <p class="landing-pricing__footnote">
          {gettext("Paid features free until the end of next month. No card required.")}
        </p>
      </div>
    </section>
    """
  end

  defp localize_plans(plans, yearly?) do
    Enum.map(plans, fn plan ->
      free? = plan.monthly == 0

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
        price: to_string(if yearly?, do: plan.yearly, else: plan.monthly),
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
