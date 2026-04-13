const SCRIPT_SELECTOR = "script[data-telemetry-config='true']";
const CONSENT_COOKIE = "cookie_consent";

function getAppScript() {
  return document.querySelector(SCRIPT_SELECTOR);
}

function readConfig() {
  const script = getAppScript();

  if (!script) {
    return {
      posthogEnabled: false,
      posthogApiKey: "",
      posthogApiHost: "",
      sentryDsn: "",
      sentryEnvironment: "",
      sentryRelease: ""
    };
  }

  return {
    posthogEnabled: script.dataset.posthogEnabled === "true",
    posthogApiKey: script.dataset.posthogApiKey || "",
    posthogApiHost: script.dataset.posthogApiHost || "",
    sentryDsn: script.dataset.sentryDsn || "",
    sentryEnvironment: script.dataset.sentryEnvironment || "",
    sentryRelease: script.dataset.sentryRelease || "",
    currentUserId: script.dataset.currentUserId || "",
    currentUserEmail: script.dataset.currentUserEmail || ""
  };
}

function getCookie(name) {
  const match = document.cookie.match(new RegExp(`(^| )${name}=([^;]+)`));
  return match ? match[2] : null;
}

function consentAccepted() {
  return getCookie(CONSENT_COOKIE) === "accepted";
}

let sentryInitialized = false;
let posthogInitialized = false;

export function initTelemetry() {
  if (!consentAccepted()) {
    return;
  }

  const config = readConfig();

  if (!sentryInitialized && config.sentryDsn) {
    const sentry = window.Sentry;

    if (!sentry) {
      return;
    }

    sentry.init({
      dsn: config.sentryDsn,
      environment: config.sentryEnvironment,
      release: config.sentryRelease || undefined,
      tracesSampleRate: 0.05
    });

    sentryInitialized = true;
  }

  if (!posthogInitialized && config.posthogEnabled && config.posthogApiKey) {
    const posthog = window.posthog;

    if (!posthog) {
      return;
    }

    posthog.init(config.posthogApiKey, {
      api_host: config.posthogApiHost,
      capture_pageview: false,
      persistence: "localStorage"
    });

    posthog.capture("pageview", {
      path: window.location.pathname,
      title: document.title
    });

    if (config.currentUserId) {
      posthog.identify(config.currentUserId, {
        email: config.currentUserEmail || undefined
      });
    }

    window.addEventListener("phx:page-loading-stop", () => {
      posthog.capture("pageview", {
        path: window.location.pathname,
        title: document.title
      });
    });

    posthogInitialized = true;
  }
}
