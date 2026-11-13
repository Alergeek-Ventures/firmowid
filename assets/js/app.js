// All JS dependencies are declared in assets/package.json. Add new ones with
// `npm install --save-exact some-package --prefix assets` and import them
// using a path starting with the package name:
//
//     import "some-package"
//
// Public pages load landing.js instead; both start LiveView through live_socket.js.

import { createLiveToastHook } from "live_toast";
import { Hooks } from "./hooks";
import { hooks as colocatedHooks } from "phoenix-colocated/firmowid";
import { startLiveSocket } from "./live_socket";
import { initTelemetry } from "./telemetry";
import { installLandingCtaTracking, installPosthogLogoutReset } from "./telemetry/posthog";

startLiveSocket({
  LiveToast: createLiveToastHook(),
  ...Hooks,
  ...colocatedHooks,
});
initTelemetry();
installPosthogLogoutReset();
installLandingCtaTracking();
