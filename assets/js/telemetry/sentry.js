import {
  addEventProcessor,
  getClient,
  getReplay,
  init,
  replayIntegration,
  setTag,
  setUser,
} from "@sentry/browser";

import { telemetryConfig } from "./config";
import { sanitizeTelemetryUrl } from "./privacy.js";

// These schema constants mirror the installed Sentry 10.73 event/Replay contracts.
const ID = /^[0-9a-f]{32}$/i;
const DEBUG_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_FINGERPRINT = "{{ default }}";
const BOOLEAN_REPLAY_OPTION_FIELDS = [
  "blockAllMedia",
  "maskAllInputs",
  "maskAllText",
  "networkCaptureBodies",
  "networkDetailHasUrls",
  "networkRequestHasHeaders",
  "networkResponseHasHeaders",
  "shouldRecordCanvas",
  "useCompression",
  "useCompressionOption",
];
const NUMERIC_REPLAY_OPTION_FIELDS = ["errorSampleRate", "sessionSampleRate"];
const CONTEXT_FIELDS = {
  browser: ["name", "version"],
  os: ["name", "version", "build", "kernel_version"],
  device: ["name", "family", "model", "brand", "arch"],
  runtime: ["name", "version"],
  trace: ["trace_id", "span_id", "parent_span_id", "op", "status", "origin", "sampled"],
  replay: ["replay_id"],
};
const FRAME_FIELDS = [
  "function",
  "module",
  "lineno",
  "colno",
  "in_app",
  "platform",
  "instruction_addr",
  "addr_mode",
  "debug_id",
];
const BREADCRUMB_DATA_FIELDS = ["method", "status_code", "url", "from", "to"];

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function scalar(value) {
  return typeof value === "string" || typeof value === "boolean" ||
    (typeof value === "number" && Number.isFinite(value));
}

function fields(value, names) {
  if (!object(value)) return {};
  const result = {};
  for (const name of names) if (scalar(value[name])) result[name] = value[name];
  return result;
}

function sanitizeUser(user) {
  if (!object(user)) return {};
  const result = {};
  if (scalar(user.id)) result.id = user.id;
  if (typeof user.ip_address === "string") result.ip_address = user.ip_address;
  return result;
}

function sanitizeRequest(request) {
  if (!object(request)) return {};
  const result = {};
  if (typeof request.url === "string") result.url = sanitizeTelemetryUrl(request.url);
  if (result.url === undefined) delete result.url;
  if (typeof request.method === "string") result.method = request.method;
  return result;
}

function sanitizeTags(tags) {
  if (!object(tags)) return {};
  return typeof tags.organization_id === "string"
    ? { organization_id: tags.organization_id }
    : {};
}

function sanitizeContexts(contexts) {
  if (!object(contexts)) return {};
  const result = {};
  for (const [name, names] of Object.entries(CONTEXT_FIELDS)) {
    if (object(contexts[name])) result[name] = fields(contexts[name], names);
  }
  return result;
}

function sanitizeBreadcrumb(breadcrumb) {
  if (!object(breadcrumb) || breadcrumb.category === "console") return null;
  const result = fields(breadcrumb, ["type", "category", "level", "timestamp"]);
  if (object(breadcrumb.data)) {
    const data = {};
    for (const name of BREADCRUMB_DATA_FIELDS) {
      if (!scalar(breadcrumb.data[name])) continue;
      if (name === "url" || name === "from" || name === "to") {
        const url = sanitizeTelemetryUrl(breadcrumb.data[name]);
        if (url !== undefined) data[name] = url;
      } else {
        data[name] = breadcrumb.data[name];
      }
    }
    if (Object.keys(data).length) result.data = data;
  }
  return Object.keys(result).length ? result : null;
}

function sanitizeStacktrace(stacktrace) {
  if (!object(stacktrace)) return {};
  const result = {};
  if (Array.isArray(stacktrace.frames_omitted) &&
    stacktrace.frames_omitted.length === 2 &&
    stacktrace.frames_omitted.every((value) => Number.isFinite(value))) {
    result.frames_omitted = [...stacktrace.frames_omitted];
  }
  if (Array.isArray(stacktrace.frames)) {
    result.frames = stacktrace.frames.filter(object).map(sanitizeFrame);
  }
  return result;
}

function sanitizeFrame(frame) {
  if (!object(frame)) return {};
  const result = fields(frame, FRAME_FIELDS);
  for (const name of ["filename", "abs_path"]) {
    if (typeof frame[name] === "string" && applicationPath(frame[name])) result[name] = frame[name];
  }
  return result;
}

function applicationPath(value) {
  try {
    const url = new URL(value, window.location.origin);
    if (url.username || url.password) return false;
    const file = url.pathname.split("/").pop();
    return url.origin === window.location.origin &&
      (url.search === "" || url.search === "?vsn=d") && !url.hash &&
      /^\/assets\/(?:app\.js|app-[0-9a-f]+\.js)$/i.test(url.pathname) && !!file;
  } catch (_error) {
    return false;
  }
}

function sanitizeDebugMeta(debugMeta) {
  if (!object(debugMeta) || !Array.isArray(debugMeta.images)) return null;
  const images = debugMeta.images
    .filter((image) => object(image) && image.type === "sourcemap" &&
      DEBUG_ID.test(image.debug_id) && typeof image.code_file === "string" &&
      applicationPath(image.code_file))
    .map((image) => ({
      type: "sourcemap",
      code_file: image.code_file,
      debug_id: image.debug_id,
    }));
  return images.length ? { images } : null;
}

function sanitizeException(exception) {
  if (!object(exception) || !Array.isArray(exception.values)) return {};
  return {
    values: exception.values.filter(object).map((value) => ({
      ...(typeof value.type === "string" ? { type: value.type } : {}),
      ...(typeof value.module === "string" ? { module: value.module } : {}),
      value: "Browser exception captured",
      ...(scalar(value.thread_id) ? { thread_id: value.thread_id } : {}),
      ...(object(value.mechanism) ? { mechanism: fields(value.mechanism, [
        "type", "handled", "synthetic", "source", "is_exception_group", "exception_id", "parent_id",
      ]) } : {}),
      ...(object(value.stacktrace) ? { stacktrace: sanitizeStacktrace(value.stacktrace) } : {}),
    })),
  };
}

function sanitizeThreads(threads) {
  if (!object(threads) || !Array.isArray(threads.values)) return {};
  return {
    values: threads.values.filter(object).map((thread) => ({
      ...fields(thread, ["id", "main", "crashed", "current"]),
      ...(object(thread.stacktrace) ? { stacktrace: sanitizeStacktrace(thread.stacktrace) } : {}),
    })),
  };
}

function sanitizeSdk(sdk) {
  if (!object(sdk)) return {};
  const result = {};
  if (typeof sdk.name === "string") result.name = sdk.name;
  if (typeof sdk.version === "string") result.version = sdk.version;
  if (Array.isArray(sdk.integrations) && sdk.integrations.every((name) => typeof name === "string")) {
    result.integrations = [...sdk.integrations];
  }
  if (Array.isArray(sdk.packages)) {
    const packages = sdk.packages
      .filter((pkg) => object(pkg) && typeof pkg.name === "string" && typeof pkg.version === "string")
      .map((pkg) => ({ name: pkg.name, version: pkg.version }));
    if (packages.length) result.packages = packages;
  }
  if (object(sdk.settings) && ["auto", "never"].includes(sdk.settings.infer_ip)) {
    result.settings = { infer_ip: sdk.settings.infer_ip };
  }
  return result;
}

function sanitizeEvent(event) {
  if (!object(event)) return null;
  const result = {};
  for (const name of ["event_id", "type", "platform", "release", "environment", "dist", "level", "logger"]) {
    if (scalar(event[name])) result[name] = event[name];
  }
  if (typeof event.timestamp === "number" && Number.isFinite(event.timestamp)) result.timestamp = event.timestamp;
  if (typeof event.message === "string") result.message = "Browser message captured";
  const currentPath = sanitizeTelemetryUrl(window.location.pathname);
  if (typeof event.transaction === "string") {
    const transaction = sanitizeTelemetryUrl(event.transaction);
    if (transaction !== undefined) result.transaction = transaction;
  } else if (typeof currentPath === "string" && currentPath !== "") {
    result.transaction = currentPath;
  }
  if (object(event.logentry) && typeof event.logentry.message === "string") {
    const logentry = {};
    logentry.message = "Browser message captured";
    result.logentry = logentry;
  }
  if ("user" in event) result.user = sanitizeUser(event.user);
  if ("request" in event) result.request = sanitizeRequest(event.request);
  if ("tags" in event) result.tags = sanitizeTags(event.tags);
  if (object(event.contexts)) result.contexts = sanitizeContexts(event.contexts);
  if (Array.isArray(event.breadcrumbs)) result.breadcrumbs = event.breadcrumbs.map(sanitizeBreadcrumb).filter(Boolean);
  if (object(event.exception)) result.exception = sanitizeException(event.exception);
  if (object(event.threads)) result.threads = sanitizeThreads(event.threads);
  if (Array.isArray(event.fingerprint) && event.fingerprint.includes(DEFAULT_FINGERPRINT)) result.fingerprint = [DEFAULT_FINGERPRINT];
  if (object(event.sdk)) result.sdk = sanitizeSdk(event.sdk);
  const debugMeta = sanitizeDebugMeta(event.debug_meta);
  if (debugMeta) result.debug_meta = debugMeta;
  return result;
}

function sanitizeReplayMetadata(event) {
  if (event?.type !== "replay_event") return event;
  try {
    if (!ID.test(event.event_id) || !ID.test(event.replay_id) ||
      !Number.isFinite(event.replay_start_timestamp) || !Number.isFinite(event.timestamp) ||
      !Number.isInteger(event.segment_id) || event.segment_id < 0 ||
      !["session", "buffer"].includes(event.replay_type) ||
      !Array.isArray(event.error_ids) || !event.error_ids.every((id) => ID.test(id)) ||
      !Array.isArray(event.trace_ids) || !event.trace_ids.every((id) => ID.test(id)) ||
      !Array.isArray(event.segment_names) || !event.segment_names.every((name) => typeof name === "string") ||
      !Array.isArray(event.urls) ||
      !event.urls.every((url) => typeof url === "string")) return null;
    const urls = event.urls.map(sanitizeTelemetryUrl);
    if (urls.some((url) => url === undefined)) return null;
    const transaction = typeof event.transaction === "string"
      ? sanitizeTelemetryUrl(event.transaction)
      : undefined;
    return {
      type: "replay_event",
      event_id: event.event_id,
      replay_start_timestamp: event.replay_start_timestamp,
      timestamp: event.timestamp,
      error_ids: [...event.error_ids],
      trace_ids: [...event.trace_ids],
      segment_names: [],
      urls,
      replay_id: event.replay_id,
      segment_id: event.segment_id,
      replay_type: event.replay_type,
      ...(typeof event.release === "string" ? { release: event.release } : {}),
      ...(typeof event.environment === "string" ? { environment: event.environment } : {}),
      ...(transaction !== undefined
        ? { transaction }
        : {}),
    };
  } catch (_error) {
    return null;
  }
}

function sanitizeRecordingEvent(event) {
  if (!object(event) || !object(event.data) ||
    event.type !== 5 || !Number.isFinite(event.timestamp)) return null;
  const { tag, payload } = event.data;
  let clean;
  if (tag === "options") {
    if (!object(payload) ||
      !BOOLEAN_REPLAY_OPTION_FIELDS.every((name) => typeof payload[name] === "boolean") ||
      !NUMERIC_REPLAY_OPTION_FIELDS.every((name) =>
        typeof payload[name] === "number" && Number.isFinite(payload[name]))) return null;
    clean = [...BOOLEAN_REPLAY_OPTION_FIELDS, ...NUMERIC_REPLAY_OPTION_FIELDS]
      .reduce((result, name) => ({ ...result, [name]: payload[name] }), {});
  } else if (tag === "performanceSpan") {
    if (!object(payload) || typeof payload.op !== "string" ||
      !Number.isFinite(payload.startTimestamp) || !Number.isFinite(payload.endTimestamp)) return null;
    clean = {
      op: payload.op,
      description: "redacted",
      startTimestamp: payload.startTimestamp,
      endTimestamp: payload.endTimestamp,
    };
  } else return null;
  if (!clean || !Object.keys(clean).length) return null;
  return {
    type: event.type,
    timestamp: event.timestamp,
    data: { tag, payload: clean },
  };
}

function beforeSend(event) {
  try {
    return sanitizeEvent(event);
  } catch (_error) {
    return null;
  }
}

function beforeBreadcrumb(event) {
  try {
    return sanitizeBreadcrumb(event);
  } catch (_error) {
    return null;
  }
}

function beforeAddRecordingEvent(event) {
  try {
    return sanitizeRecordingEvent(event);
  } catch (_error) {
    return null;
  }
}

export function initSentry() {
  if (getClient() || !telemetryConfig.sentryDsn) return;
  init({
    dsn: telemetryConfig.sentryDsn,
    tunnel: "/_x/8e2f",
    environment: telemetryConfig.sentryEnvironment,
    release: telemetryConfig.sentryRelease || undefined,
    sendDefaultPii: false,
    enableLogs: false,
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: {
        request: false,
        response: false,
      },
      httpBodies: [],
      urlQueryParams: false,
      graphQL: {
        document: false,
        variables: false,
      },
      genAI: {
        inputs: false,
        outputs: false,
      },
      databaseQueryData: false,
      stackFrameVariables: false,
      frameContextLines: 0,
    },
    beforeSend,
    beforeBreadcrumb,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
  });
  addEventProcessor(sanitizeReplayMetadata);
  if (telemetryConfig.currentUserId) {
    setUser({ id: telemetryConfig.currentUserId });
  }
  if (telemetryConfig.currentOrganizationId) {
    setTag("organization_id", telemetryConfig.currentOrganizationId);
  }
}

export function enableSentryReplay() {
  const client = getClient();
  if (!client) return;
  const replay = getReplay();
  if (replay) {
    replay.startBuffering();
    return;
  }
  const options = client.getOptions();
  options.replaysSessionSampleRate = 0;
  options.replaysOnErrorSampleRate = 1;
  client.addIntegration(
    replayIntegration({
      maskAllText: true,
      maskAllInputs: true,
      blockAllMedia: true,
      networkDetailAllowUrls: [],
      networkCaptureBodies: false,
      networkRequestHeaders: [],
      networkResponseHeaders: [],
      attachRawBodyFromRequest: false,
      maskAttributes: [
        "title",
        "placeholder",
        "aria-label",
        "alt",
        "download",
        "onclick",
        "href",
        "src",
        "srcset",
        "action",
        "formaction",
        "poster",
        "xlink:href",
        "data-autocomplete-data",
        "data-download-url",
        "data-tippy-content",
        "data-bank",
        "data-start_time",
        "data-initial-date",
        "data-enabled-months",
        "data-enabled-years",
        "data-value",
        "data-pdf-url",
        "data-fa3-url",
        "phx-value-reason",
        "phx-value-message",
        "phx-value-suggestion",
        "phx-value-email",
        "phx-value-number",
        "phx-value-code",
        "phx-value-ref",
        "phx-value-value",
      ],
      block: ["script[data-telemetry-config='true']"],
      beforeAddRecordingEvent,
    }),
  );
}

export function disableSentryReplay() {
  const replay = getReplay();
  if (replay) {
    void replay.stop({ flush: false });
  }
}
