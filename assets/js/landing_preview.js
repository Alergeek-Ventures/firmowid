// Telemetry for the static home page and the KSeF pricing page. Each has
// its own script and no LiveView, so this bundle carries PostHog alone. Nothing
// is loaded into PostHog or sent until the visitor has accepted analytics.

import { consentAccepted } from "./telemetry/consent";
import {
  bootPosthog,
  installLandingCalculatorTracking,
  installLandingCtaTracking,
} from "./telemetry/posthog";

if (consentAccepted()) {
  bootPosthog();
  installLandingCtaTracking();
  installLandingCalculatorTracking();
}
