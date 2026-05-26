import {
  acceptConsent,
  consentStatus,
  rejectConsent
} from "../telemetry/consent";
import { acceptTelemetry, optOutTelemetry } from "../telemetry";

/**
 * CookieConsent Hook
 *
 * Shows the cookie consent banner if no preference has been stored yet.
 * On accept/reject, sets a `cookie_consent` cookie (max-age: 1 year)
 * readable by the server for analytics gating.
 *
 * Values: "accepted" | "rejected"
 *
 * @type {import("phoenix_live_view").ViewHook}
 */
export const CookieConsent = {
  mounted() {
    const existing = consentStatus();

    if (!existing) {
      this.el.classList.remove("hidden");
    }

    this.el
      .querySelector("#cookie-consent-accept")
      .addEventListener("click", () => {
        acceptConsent();
        acceptTelemetry();
        this.el.classList.add("hidden");
      });

    this.el
      .querySelector("#cookie-consent-reject")
      .addEventListener("click", () => {
        rejectConsent();
        optOutTelemetry();
        this.el.classList.add("hidden");
      });
  },
};
