const SENSITIVE_ROUTES = new Set(["resetuj-haslo", "potwierdz-email", "faktura"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HEX_ID = /^[0-9a-f]{32}$/i;

function redactPathname(pathname) {
  const segments = pathname.split("/");
  let redactNext = false;

  return segments.map((segment) => {
    const decodedSegment = decodeURIComponent(segment);
    if (redactNext) {
      redactNext = false;
      if (segment !== "") return ":redacted";
    }
    if (SENSITIVE_ROUTES.has(decodedSegment.toLowerCase())) {
      redactNext = true;
      return segment;
    }
    return UUID.test(decodedSegment) || HEX_ID.test(decodedSegment) ? ":id" : segment;
  }).join("/");
}

/** Return a query- and hash-free URL safe for telemetry. */
export function sanitizeTelemetryUrl(value) {
  if (typeof value !== "string" || (!value.startsWith("/") && !/^https?:\/\//i.test(value))) {
    return undefined;
  }

  try {
    const parsed = new URL(value, window.location.origin);
    if (!/^https?:$/.test(parsed.protocol)) return undefined;
    if (value.startsWith("/") && parsed.origin !== window.location.origin) return undefined;
    if (parsed.username || parsed.password) return undefined;
    parsed.search = "";
    parsed.hash = "";
    parsed.pathname = redactPathname(parsed.pathname);
    return parsed.origin === window.location.origin ? parsed.pathname : parsed.href;
  } catch (_error) {
    return undefined;
  }
}
