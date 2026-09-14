import { sanitizeTelemetryUrl } from "./privacy.js";

const URL_PROPERTIES = [
  "$current_url", "$initial_current_url", "$referrer", "$initial_referrer",
  "$external_click_url", "$session_entry_url", "$session_entry_referrer",
];
const PATHNAME_PROPERTIES = ["$pathname", "$session_entry_pathname", "$prev_pageview_pathname"];
const PERSON_PROPERTIES = ["$set", "$set_once"];
const EMAIL_KEYS = new Set(["email", "email_domain", "$email", "$email_domain"]);
const REMOVED_KEYS = new Set([
  ...EMAIL_KEYS,
  "$el_text", "$selected_content", "title", "$search_keyword", "$raw_user_agent",
  "$sdk_debug_error_capturing_properties",
]);

function plainObject(value) {
  if (value === null || typeof value !== "object") return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function clone(value) {
  if (Array.isArray(value)) return value.map(clone);
  if (plainObject(value)) return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clone(item)]));
  if (value instanceof Date) return new Date(value.getTime());
  return value;
}

function sanitizeNested(value) {
  if (Array.isArray(value)) return value.map(sanitizeNested);
  if (!plainObject(value)) return clone(value);

  const result = {};
  for (const [key, item] of Object.entries(value)) {
    if (key !== "token" && (REMOVED_KEYS.has(key) || key.startsWith("attr__"))) continue;
    result[key] = sanitizeNested(item);
  }
  return result;
}

function scalar(value) {
  return typeof value === "string" || typeof value === "boolean" ||
    (typeof value === "number" && Number.isFinite(value));
}

function sanitizePersonProperties(properties) {
  if (!plainObject(properties)) return null;
  const result = {};
  for (const key of ["organization_id", "role"]) {
    if (scalar(properties[key])) result[key] = properties[key];
  }
  return result;
}

function sanitizePersonLocation(properties, key) {
  if (!(key in properties)) return;
  const personProperties = sanitizePersonProperties(properties[key]);
  if (personProperties === null) delete properties[key];
  else properties[key] = personProperties;
}

function sanitizeElementsChain(chain) {
  if (typeof chain !== "string") return undefined;

  const attribute = /([A-Za-z_$][A-Za-z0-9_$-]*)="([^"]*)"/g;
  const sanitized = chain.replace(attribute, (match, name, value) =>
    ["nth-child", "nth-of-type"].includes(name) && /^\d+$/.test(value) ? match : "",
  );
  const remainder = sanitized.replace(/(?:nth-child|nth-of-type)="\d+"/g, "");
  return /["']/.test(remainder) ? undefined : sanitized;
}

function sanitizeProperties(properties) {
  if (!plainObject(properties)) return null;
  const result = sanitizeNested(properties);
  for (const key of URL_PROPERTIES) {
    if (!(key in result)) continue;
    const url = sanitizeTelemetryUrl(result[key], { output: "absolute" });
    if (url === undefined) delete result[key];
    else result[key] = url;
  }
  for (const key of PATHNAME_PROPERTIES) {
    if (!(key in result)) continue;
    const url = sanitizeTelemetryUrl(result[key], { output: "pathname" });
    if (url === undefined) delete result[key];
    else result[key] = url;
  }
  for (const key of PERSON_PROPERTIES) sanitizePersonLocation(result, key);
  if ("$elements" in result) {
    if (!Array.isArray(result.$elements)) delete result.$elements;
    else result.$elements = result.$elements.filter(plainObject).map((element) => {
      const structural = {};
      if (typeof element.tag_name === "string") structural.tag_name = element.tag_name;
      if (Array.isArray(element.classes) && element.classes.every((value) => typeof value === "string")) {
        structural.classes = [...element.classes];
      }
      for (const field of ["nth_child", "nth_of_type"]) {
        if (Number.isInteger(element[field]) && Number.isFinite(element[field])) structural[field] = element[field];
      }
      return structural;
    });
  }
  if ("$elements_chain" in result) {
    const chain = sanitizeElementsChain(result.$elements_chain);
    if (chain === undefined) delete result.$elements_chain;
    else result.$elements_chain = chain;
  }
  return result;
}

/** Clone and sanitize a PostHog event, or return null for malformed events. */
export function sanitizePosthogEvent(event) {
  try {
    if (!plainObject(event) || typeof event.uuid !== "string" || !event.uuid ||
      typeof event.event !== "string" || !event.event || !plainObject(event.properties) ||
      typeof event.properties.token !== "string" || !event.properties.token ||
      !(event.timestamp instanceof Date) || Number.isNaN(event.timestamp.getTime())) return null;
    const result = {
      uuid: event.uuid,
      event: event.event,
      properties: sanitizeProperties(event.properties),
      timestamp: new Date(event.timestamp.getTime()),
    };
    if (!result.properties) return null;
    for (const key of PERSON_PROPERTIES) {
      if (key in event) {
        const personProperties = sanitizePersonProperties(event[key]);
        if (personProperties !== null) result[key] = personProperties;
      }
    }
    return result;
  } catch (_error) {
    return null;
  }
}
