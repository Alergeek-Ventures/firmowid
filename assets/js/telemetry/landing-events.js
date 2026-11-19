// What the public pages may report: a fixed list of names and plain numbers.
// Anything outside these lists is dropped before it reaches PostHog.

const LANDING_CTAS = new Set([
  // Home page
  "hero_register",
  "hero_login",
  "navbar_trial",
  "pricing_register",
  "footer_register",
  "footer_demo_booking",
  // Preview of the new home page
  "navbar_login",
  "hero_trial",
  "pricing_free",
  "pricing_przedsiebiorca",
  "pricing_firma",
  "final_trial",
  "demo_booking",
  "case_study_request",
  "case_bonobo",
  "github",
  "open_source",
]);
const LANDING_PLANS = new Set(["start", "przedsiebiorca", "firma"]);
const LANDING_BILLING_PERIODS = new Set(["monthly", "yearly"]);

/** Properties of `landing_cta_clicked` for an element's dataset, or null when it is not a known CTA. */
export function landingCtaProperties(dataset) {
  const cta = dataset?.landingCta;
  if (!LANDING_CTAS.has(cta)) return null;

  const properties = { cta };
  if (cta === "pricing_register") {
    if (!LANDING_PLANS.has(dataset.landingPlan) ||
      !LANDING_BILLING_PERIODS.has(dataset.landingBillingPeriod)) return null;
    properties.plan = dataset.landingPlan;
    properties.billing_period = dataset.landingBillingPeriod;
  }
  return properties;
}

export const LANDING_CALCULATOR_EVENT = "firmowid:calculator";

const CALCULATOR_STEPS = new Set([1, 2, 3]);
const CALCULATOR_NUMBERS = {
  team_size: (value) => Number.isInteger(value) && value >= 1,
  tools_cost_per_year: (value) => value >= 0,
  hours_per_week: (value) => value > 0,
  hourly_cost: (value) => value > 0,
  savings_per_year: () => true,
};

/** Name and properties of the event for what the cost calculator announced, or null. */
export function landingCalculatorEvent(detail) {
  if (detail?.type === "step") {
    return CALCULATOR_STEPS.has(detail.step)
      ? { name: "landing_calculator_step", properties: { step: detail.step } }
      : null;
  }

  if (detail?.type !== "completed") return null;

  const properties = {};
  for (const [key, valid] of Object.entries(CALCULATOR_NUMBERS)) {
    const value = detail[key];
    if (typeof value !== "number" || !Number.isFinite(value) || !valid(value)) return null;
    properties[key] = value;
  }
  return { name: "landing_calculator_completed", properties };
}
