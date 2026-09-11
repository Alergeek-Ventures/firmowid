import { z } from "zod";

const SCRIPT_SELECTOR = "script[data-telemetry-config='true']";

const datasetBoolean = z.preprocess((value) => value === "true", z.boolean());
const datasetString = z.preprocess(
  (value) => (typeof value === "string" ? value : ""),
  z.string()
);

const telemetryConfigSchema = z.object({
  posthogEnabled: datasetBoolean,
  posthogApiKey: datasetString,
  publicMarketing: datasetBoolean,
  currentUserId: datasetString,
  currentUserRole: datasetString,
  currentOrganizationId: datasetString,
  sentryDsn: datasetString,
  sentryEnvironment: datasetString,
  sentryRelease: datasetString
});

function getAppScript() {
  return document.querySelector(SCRIPT_SELECTOR);
}

function readTelemetryConfig() {
  return telemetryConfigSchema.parse(getAppScript()?.dataset ?? {});
}

function currentUserProperties(config) {
  return {
    role: config.currentUserRole || undefined,
    organization_id: config.currentOrganizationId || undefined
  };
}

function analyticsContextProperties(config) {
  return {
    surface: config.publicMarketing ? "landing" : "app",
    auth_state: config.currentUserId ? "identified" : "anonymous"
  };
}

export const telemetryConfig = readTelemetryConfig();
export const telemetryUserProperties = currentUserProperties(telemetryConfig);
export const telemetryContextProperties = analyticsContextProperties(telemetryConfig);
