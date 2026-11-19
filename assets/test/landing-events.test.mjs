import assert from "node:assert/strict";
import { test } from "node:test";

import { landingCtaProperties } from "../js/telemetry/landing-events.js";

test("home page calls to action keep their names", () => {
  for (const cta of ["hero_register", "hero_login", "navbar_trial", "footer_register", "footer_demo_booking"]) {
    assert.deepEqual(landingCtaProperties({ landingCta: cta }), { cta });
  }

  assert.deepEqual(
    landingCtaProperties({
      landingCta: "pricing_register",
      landingPlan: "firma",
      landingBillingPeriod: "yearly",
    }),
    { cta: "pricing_register", plan: "firma", billing_period: "yearly" },
  );
});

test("every call to action of the home page has a name", () => {
  const ctas = [
    "navbar_login", "navbar_trial", "hero_trial", "pricing_free", "pricing_przedsiebiorca",
    "pricing_firma", "final_trial", "demo_booking", "case_study_request", "case_bonobo",
    "github", "open_source",
  ];

  for (const cta of ctas) assert.deepEqual(landingCtaProperties({ landingCta: cta }), { cta });
});

test("unknown names and incomplete pricing clicks are not sent", () => {
  assert.equal(landingCtaProperties({ landingCta: "anything_else" }), null);
  assert.equal(landingCtaProperties({}), null);
  assert.equal(landingCtaProperties({ landingCta: "pricing_register", landingPlan: "firma" }), null);
});
