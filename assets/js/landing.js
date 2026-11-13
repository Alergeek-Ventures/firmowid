// Bundle for the public marketing pages (home, pricing, guides, legal pages).
// It carries LiveView and only the hooks those pages render, so a guide does not
// download the whole application. Pages outside `public_marketing?` load app.js.

import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "topbar";
import { createLiveToastHook } from "live_toast";
import Popover from "./hooks/popover";
import { CopyToClipboard } from "./hooks/copy_to_clipboard";
import { CookieConsent } from "./hooks/cookie_consent";
import { LandingNavbarTheme } from "./hooks/landing_navbar_theme";
import { LandingHero } from "./hooks/landing_hero";
import { LandingPricing } from "./hooks/landing_pricing";
import { NumberPopIn } from "./hooks/number_pop_in";
import { ImageLoadReveal } from "./hooks/image_load_reveal";
import { initTelemetry } from "./telemetry";
import { installLandingCtaTracking, installPosthogLogoutReset } from "./telemetry/posthog";

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  },
  hooks: {
    LiveToast: createLiveToastHook(),
    Popover,
    CopyToClipboard,
    CookieConsent,
    LandingNavbarTheme,
    LandingHero,
    LandingPricing,
    NumberPopIn,
    ImageLoadReveal,
  },
});

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

window.addEventListener("phx:js-exec", ({ detail }) => {
  document.querySelectorAll(detail.to).forEach((el) => {
    liveSocket.execJS(el, el.getAttribute(detail.attr));
  });
});

liveSocket.connect();
initTelemetry();
installPosthogLogoutReset();
installLandingCtaTracking();

window.liveSocket = liveSocket;
