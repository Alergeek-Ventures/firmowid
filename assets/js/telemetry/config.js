const SCRIPT_SELECTOR = "script[data-telemetry-config='true']";

// The server writes every value as a data attribute, so each one arrives as a
// string or not at all.
function datasetBoolean(value) {
  return value === "true";
}

function datasetString(value) {
  return typeof value === "string" ? value : "";
}

function getAppScript() {
  return document.querySelector(SCRIPT_SELECTOR);
}

function readTelemetryConfig() {
  const dataset = getAppScript()?.dataset ?? {};

  return {
    posthogEnabled: datasetBoolean(dataset.posthogEnabled),
    posthogApiKey: datasetString(dataset.posthogApiKey),
    publicMarketing: datasetBoolean(dataset.publicMarketing),
    currentUserId: datasetString(dataset.currentUserId),
    currentUserRole: datasetString(dataset.currentUserRole),
    currentOrganizationId: datasetString(dataset.currentOrganizationId),
    currentOrganizationPlan: datasetString(dataset.currentOrganizationPlan),
    sentryDsn: datasetString(dataset.sentryDsn),
    sentryEnvironment: datasetString(dataset.sentryEnvironment),
    sentryRelease: datasetString(dataset.sentryRelease)
  };
}

function currentUserProperties(config) {
  return {
    role: config.currentUserRole || undefined,
    organization_id: config.currentOrganizationId || undefined,
    plan: config.currentOrganizationPlan || undefined
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
