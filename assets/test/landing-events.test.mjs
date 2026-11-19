import assert from "node:assert/strict";
import { test } from "node:test";

import { landingCalculatorEvent, landingCtaProperties } from "../js/telemetry/landing-events.js";

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

test("a calculator step carries only its number", () => {
  for (const step of [1, 2, 3]) {
    assert.deepEqual(landingCalculatorEvent({ type: "step", step }), {
      name: "landing_calculator_step",
      properties: { step },
    });
  }

  assert.equal(landingCalculatorEvent({ type: "step", step: 4 }), null);
  assert.equal(landingCalculatorEvent({ type: "step", step: "1" }), null);
});

test("a completed calculation carries the numbers shown on the page and nothing else", () => {
  const detail = {
    type: "completed",
    team_size: 6,
    tools_cost_per_year: 1188,
    hours_per_week: 5.5,
    hourly_cost: 150,
    savings_per_year: 21210,
    note: "typed text never leaves the page",
  };

  assert.deepEqual(landingCalculatorEvent(detail), {
    name: "landing_calculator_completed",
    properties: {
      team_size: 6,
      tools_cost_per_year: 1188,
      hours_per_week: 5.5,
      hourly_cost: 150,
      savings_per_year: 21210,
    },
  });
});

test("a calculation with a missing or malformed number is not sent", () => {
  const valid = {
    type: "completed",
    team_size: 6,
    tools_cost_per_year: 0,
    hours_per_week: 5,
    hourly_cost: 150,
    savings_per_year: -1428,
  };

  assert.notEqual(landingCalculatorEvent(valid), null);
  assert.equal(landingCalculatorEvent({ ...valid, team_size: "6" }), null);
  assert.equal(landingCalculatorEvent({ ...valid, hourly_cost: Number.NaN }), null);
  assert.equal(landingCalculatorEvent({ ...valid, tools_cost_per_year: -1 }), null);
  assert.equal(landingCalculatorEvent({ ...valid, savings_per_year: undefined }), null);
  assert.equal(landingCalculatorEvent({ type: "other" }), null);
  assert.equal(landingCalculatorEvent(null), null);
});
