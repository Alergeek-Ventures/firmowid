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
