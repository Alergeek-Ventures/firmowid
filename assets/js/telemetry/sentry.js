import {
  getClient,
  getReplay,
  init,
  replayIntegration
} from "@sentry/browser";

import { telemetryConfig } from "./config";

export function initSentry() {
  if (getClient() || !telemetryConfig.sentryDsn) {
    return;
  }

  init({
    dsn: telemetryConfig.sentryDsn,
    environment: telemetryConfig.sentryEnvironment,
    release: telemetryConfig.sentryRelease || undefined,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0
  });
}

export function enableSentryReplay() {
  const client = getClient();

  if (!client || getReplay()) {
    return;
  }

  const options = client.getOptions();
  options.replaysSessionSampleRate = 0;
  options.replaysOnErrorSampleRate = 1.0;

  client.addIntegration(
    replayIntegration({
      maskAllText: true,
      blockAllMedia: true
    })
  );
}

export function disableSentryReplay() {
  void getReplay()?.stop({ flush: false });
}
