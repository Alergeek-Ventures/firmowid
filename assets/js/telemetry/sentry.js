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
    replaysOnErrorSampleRate: 0,
    integrations: [
      replayIntegration({
        maskAllText: true,
        blockAllMedia: true
      })
    ]
  });

}

export function enableSentryReplay() {
  void getReplay()?.start();
}

export function disableSentryReplay() {
  void getReplay()?.stop();
}
