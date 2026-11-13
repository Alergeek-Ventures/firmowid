// Bundle for the public marketing pages (home, pricing, guides, legal pages).
// It carries LiveView and only the hooks those pages render, so a guide does not
// download the whole application. Pages outside `public_marketing?` load app.js.
// FirmowidWeb.Landing.Views.PublicHooksTest fails when a public page renders a
// hook missing from this list.

import { createLiveToastHook } from "live_toast";
import Popover from "./hooks/popover";
import { CopyToClipboard } from "./hooks/copy_to_clipboard";
import { CookieConsent } from "./hooks/cookie_consent";
import { LandingNavbarTheme } from "./hooks/landing_navbar_theme";
import { LandingHero } from "./hooks/landing_hero";
import { LandingPricing } from "./hooks/landing_pricing";
import { NumberPopIn } from "./hooks/number_pop_in";
import { ImageLoadReveal } from "./hooks/image_load_reveal";
import { startLiveSocket } from "./live_socket";
import { initTelemetry } from "./telemetry";
import { installLandingCtaTracking, installPosthogLogoutReset } from "./telemetry/posthog";

startLiveSocket({
  LiveToast: createLiveToastHook(),
  Popover,
  CopyToClipboard,
  CookieConsent,
  LandingNavbarTheme,
  LandingHero,
  LandingPricing,
  NumberPopIn,
  ImageLoadReveal,
});
initTelemetry();
installPosthogLogoutReset();
installLandingCtaTracking();
