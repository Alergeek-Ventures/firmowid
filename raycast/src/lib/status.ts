import { DurationFormat } from "@formatjs/intl-durationformat";
import { launchCommand, LaunchType } from "@raycast/api";

import type { Session } from "./api";
import { getOrigin } from "./auth";

const durationFormatter = new DurationFormat("en-US", {
  style: "digital",
  hoursDisplay: "always",
  secondsDisplay: "auto",
});

export function duration(session: Session): string {
  const start = Date.parse(session.start_datetime);

  const end = session.end_datetime
    ? Date.parse(session.end_datetime)
    : Date.now();

  return formatDuration(end - start);
}

export function formatDuration(milliseconds: number): string {
  const minutes = Math.floor(milliseconds / (60 * 1000));

  return durationFormatter.format({
    hours: Math.trunc(minutes / 60),
    minutes: minutes % 60,
  });
}

export function refreshMenuBar() {
  return launchCommand({ name: "session-status", type: LaunchType.Background });
}

export function timetrackerUrl() {
  return `${getOrigin()}/czasosledz`;
}
