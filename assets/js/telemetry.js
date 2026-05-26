import { consentAccepted, consentRejected } from "./telemetry/consent";
import {
  acceptPosthog,
  bootPosthog,
  optOutPosthog
} from "./telemetry/posthog";
import {
  disableSentryReplay,
  enableSentryReplay,
  initSentry
} from "./telemetry/sentry";

export function initTelemetry() {
  initSentry();

  if (consentRejected()) {
    return;
  }

  bootPosthog();

  if (consentAccepted()) {
    enableSentryReplay();
  }
}

export function acceptTelemetry() {
  enableSentryReplay();
  acceptPosthog();
}

export function optOutTelemetry() {
  disableSentryReplay();
  optOutPosthog();
}
