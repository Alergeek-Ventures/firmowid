import posthog from "posthog-js";

import { consentAccepted } from "./consent";
import {
  telemetryConfig,
  telemetryContextProperties,
  telemetryUserProperties,
} from "./config";
import { sanitizePosthogEvent } from "./posthog-privacy.js";
import { sanitizeTelemetryUrl } from "./privacy.js";

function currentTelemetryUrl() {
  return sanitizeTelemetryUrl(window.location.href, { output: "absolute" }) || window.location.origin;
}

function posthogOptions() {
  return {
    api_host: window.location.origin,
    rewriteRequestPath: (url) => {
      const paths = {
        "/i/v0/e/": "/_x/19a4/",
        "/e/": "/_x/27bf/",
        "/s/": "/_x/3d81/",
        "/flags/": "/_x/4c6e/",
        "/array/": "/_x/5ab2/",
        "/static/": "/_x/6f93/"
      };

      const entry = Object.entries(paths).find(([original]) => url.pathname.startsWith(original));

      if (entry) {
        url.pathname = entry[1] + url.pathname.slice(entry[0].length);
      }

      return url;
    },
    defaults: "2026-01-30",
    capture_pageview: "history_change",
    // Autocapture stays enabled; future data-ph-capture-attribute-* properties require privacy review.
    autocapture: { capture_copied_text: false },
    mask_all_text: true,
    mask_all_element_attributes: true,
    disable_capture_url_hashes: true,
    get_current_url: currentTelemetryUrl,
    capture_exceptions: false,
    before_send: sanitizePosthogEvent,
    persistence: consentAccepted() ? "localStorage+cookie" : "memory",
    person_profiles: "identified_only",
    disable_session_recording: true,
    disable_surveys: true,
    advanced_disable_feature_flags: true,
  };
}

function applyIdentifiedState() {
  if (!consentAccepted()) {
    return;
  }

  posthog.opt_in_capturing();
  posthog.set_config({ persistence: "localStorage+cookie" });

  if (telemetryConfig.currentUserId) {
    posthog.identify(telemetryConfig.currentUserId, telemetryUserProperties);
  }

  if (telemetryConfig.currentOrganizationId) {
    if (telemetryConfig.currentOrganizationPlan) {
      posthog.group("organization", telemetryConfig.currentOrganizationId, {
        plan: telemetryConfig.currentOrganizationPlan
      });
    } else {
      posthog.group("organization", telemetryConfig.currentOrganizationId);
    }
  }
}

function telemetryResetForm(element) {
  if (!(element instanceof HTMLFormElement)) {
    return null;
  }

  return element.dataset.posthogResetOnSubmit === "true" ? element : null;
}

const LANDING_CTAS = new Map([
  ["hero_register", { cta: "hero_register" }],
  ["hero_login", { cta: "hero_login" }],
  ["navbar_trial", { cta: "navbar_trial" }],
  ["pricing_register", { cta: "pricing_register" }],
  ["footer_register", { cta: "footer_register" }],
  ["footer_demo_booking", { cta: "footer_demo_booking" }],
]);
const LANDING_PLANS = new Set(["start", "przedsiebiorca", "firma"]);
const LANDING_BILLING_PERIODS = new Set(["monthly", "yearly"]);
let landingCtaTrackingInstalled = false;

function landingCtaProperties(element) {
  const cta = LANDING_CTAS.get(element.dataset.landingCta);
  if (!cta) return null;

  const properties = { ...cta };
  if (element.dataset.landingCta === "pricing_register") {
    if (!LANDING_PLANS.has(element.dataset.landingPlan) ||
      !LANDING_BILLING_PERIODS.has(element.dataset.landingBillingPeriod)) return null;
    properties.plan = element.dataset.landingPlan;
    properties.billing_period = element.dataset.landingBillingPeriod;
  }
  return properties;
}

/** Install the delegated, semantic landing CTA tracker once. */
export function installLandingCtaTracking() {
  if (landingCtaTrackingInstalled) return;
  landingCtaTrackingInstalled = true;

  document.addEventListener("click", (event) => {
    if (!telemetryConfig.posthogEnabled || !telemetryConfig.posthogApiKey ||
      !consentAccepted() || !(event.target instanceof Element)) return;
    const element = event.target.closest("[data-landing-cta]");
    if (!element || !element.closest('[data-landing-page="true"]')) return;
    const properties = landingCtaProperties(element);
    if (properties) {
      try {
        posthog.capture("landing_cta_clicked", properties);
      } catch (_error) {
        // Analytics must never interfere with the CTA's navigation.
      }
    }
  });
}

export function bootPosthog() {
  if (!telemetryConfig.posthogEnabled || !telemetryConfig.posthogApiKey) {
    return;
  }

  posthog.init(telemetryConfig.posthogApiKey, posthogOptions());
  posthog.register(telemetryContextProperties);
  applyIdentifiedState();
}

export function acceptPosthog() {
  if (!telemetryConfig.posthogEnabled || !telemetryConfig.posthogApiKey) {
    return;
  }

  applyIdentifiedState();
}

export function optOutPosthog() {
  posthog.reset();
  posthog.opt_out_capturing();
}

function resetPosthog() {
  posthog.reset();
}

export function installPosthogLogoutReset() {
  document.addEventListener(
    "submit",
    (event) => {
      if (telemetryResetForm(event.target)) {
        resetPosthog();
      }
    },
    true,
  );
}
