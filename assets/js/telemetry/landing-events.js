// What the public pages may report: a fixed list of names.
// Anything outside this list is dropped before it reaches PostHog.

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
