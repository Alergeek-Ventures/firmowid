const SCRIPT_SELECTOR = "script[data-telemetry-config='true']";
const CONSENT_COOKIE = "cookie_consent";
const SENTRY_SCRIPT_SRC =
  "https://browser.sentry-cdn.com/10.22.0/bundle.tracing.replay.min.js";
const POSTHOG_SCRIPT_SRC =
  "https://cdn.jsdelivr.net/npm/posthog-js@1.296.0/dist/array.full.no-external.min.js";

let sentryScriptPromise = null;
let posthogScriptPromise = null;
let anonymousLandingScheduled = false;
let anonymousLandingInitialized = false;
let anonymousLandingClickTrackingInstalled = false;

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
    publicMarketing: script.dataset.publicMarketing === "true",
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

function loadScript(src, options = {}) {
  const existingScript = document.querySelector(`script[src="${src}"]`);

  if (existingScript) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement("script");

    script.src = src;
    script.async = true;

    if (options.crossOrigin) {
      script.crossOrigin = options.crossOrigin;
    }

    script.addEventListener("load", resolve, { once: true });
    script.addEventListener("error", reject, { once: true });

    document.head.appendChild(script);
  });
}

async function ensureSentryScript() {
  sentryScriptPromise ||= loadScript(SENTRY_SCRIPT_SRC, {
    crossOrigin: "anonymous"
  });

  return sentryScriptPromise;
}

async function ensurePosthogScript() {
  posthogScriptPromise ||= loadScript(POSTHOG_SCRIPT_SRC);

  return posthogScriptPromise;
}

function runWhenIdle(callback) {
  if ("requestIdleCallback" in window) {
    window.requestIdleCallback(callback, { timeout: 3000 });
    return;
  }

  window.setTimeout(callback, 2000);
}

function pageviewProperties(mode) {
  return {
    path: window.location.pathname,
    title: document.title,
    analytics_mode: mode
  };
}

function clickedElement(event) {
  const target = event.target;

  if (!(target instanceof Element)) {
    return null;
  }

  return target.closest("a[href], button[phx-click]");
}

function sanitizedHref(element) {
  const href = element.getAttribute("href");

  if (!href) {
    return null;
  }

  if (href.startsWith("mailto:")) {
    return "mailto";
  }

  if (href.startsWith("tel:")) {
    return "tel";
  }

  try {
    const url = new URL(href, window.location.origin);

    return url.origin === window.location.origin ? url.pathname : url.origin;
  } catch (_error) {
    return "invalid";
  }
}

function landingSection(element) {
  return element.closest("section[id], header[id]")?.id || "unknown";
}

function installAnonymousLandingClickTracking(posthogInstance) {
  if (anonymousLandingClickTrackingInstalled) {
    return;
  }

  anonymousLandingClickTrackingInstalled = true;

  document.addEventListener(
    "click",
    (event) => {
      if (consentAccepted()) {
        return;
      }

      const element = clickedElement(event);

      if (!element) {
        return;
      }

      posthogInstance.capture("landing_interaction", {
        ...pageviewProperties("anonymous_memory"),
        element: element.tagName.toLowerCase(),
        text: element.textContent.trim().replace(/\s+/g, " ").slice(0, 80),
        href: sanitizedHref(element),
        phx_click: element.getAttribute("phx-click"),
        section: landingSection(element)
      });
    },
    { capture: true }
  );
}

function initAnonymousLandingTelemetry(config) {
  if (
    anonymousLandingInitialized ||
    anonymousLandingScheduled ||
    !config.posthogEnabled ||
    !config.posthogApiKey
  ) {
    return;
  }

  anonymousLandingScheduled = true;

  runWhenIdle(async () => {
    if (consentAccepted() || anonymousLandingInitialized) {
      return;
    }

    try {
      await ensurePosthogScript();
    } catch (_error) {
      // Keep the landing page functional when the analytics CDN is blocked or unavailable.
      return;
    }

    const posthog = window.posthog;

    if (!posthog) {
      return;
    }

    posthog.init(
      config.posthogApiKey,
      {
        api_host: config.posthogApiHost,
        capture_pageview: false,
        persistence: "memory",
        person_profiles: "identified_only",
        disable_session_recording: true,
        autocapture: false,
        advanced_disable_feature_flags: true,
        disable_surveys: true
      },
      "landing"
    );

    posthog.landing?.capture(
      "pageview",
      pageviewProperties("anonymous_memory")
    );

    if (posthog.landing) {
      installAnonymousLandingClickTracking(posthog.landing);
    }

    anonymousLandingInitialized = true;
  });
}

export async function initTelemetry() {
  const config = readConfig();

  if (!consentAccepted()) {
    if (config.publicMarketing) {
      initAnonymousLandingTelemetry(config);
    }

    return;
  }

  if (!sentryInitialized && config.sentryDsn) {
    try {
      await ensureSentryScript();
    } catch (_error) {
      // Keep the app functional when the analytics CDN is blocked or unavailable.
    }

    const sentry = window.Sentry;

    if (sentry) {
      sentry.init({
        dsn: config.sentryDsn,
        environment: config.sentryEnvironment,
        release: config.sentryRelease || undefined,
        tracesSampleRate: 0.05
      });

      sentryInitialized = true;
    }
  }

  if (!posthogInitialized && config.posthogEnabled && config.posthogApiKey) {
    try {
      await ensurePosthogScript();
    } catch (_error) {
      // Keep the app functional when the analytics CDN is blocked or unavailable.
    }

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
      ...pageviewProperties("consented")
    });

    if (config.currentUserId) {
      posthog.identify(config.currentUserId, {
        email: config.currentUserEmail || undefined
      });
    }

    window.addEventListener("phx:page-loading-stop", () => {
      posthog.capture("pageview", {
        ...pageviewProperties("consented")
      });
    });

    posthogInitialized = true;
  }
}
