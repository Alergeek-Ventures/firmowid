import posthog from "posthog-js";

import { consentAccepted } from "./consent";
import {
  telemetryConfig,
  telemetryContextProperties,
  telemetryUserProperties,
} from "./config";

function posthogOptions() {
  return {
    api_host: telemetryConfig.posthogApiHost,
    defaults: "2026-01-30",
    capture_pageview: "history_change",
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
}

function telemetryResetForm(element) {
  if (!(element instanceof HTMLFormElement)) {
    return null;
  }

  return element.dataset.posthogResetOnSubmit === "true" ? element : null;
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
