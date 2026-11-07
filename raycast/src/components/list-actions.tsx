import {
  Action,
  ActionPanel,
  Icon,
  Keyboard,
  showToast,
  Toast,
} from "@raycast/api";
import { useQueryClient } from "@tanstack/react-query";

import { refreshMenuBar, timetrackerUrl } from "../lib/status";

export default function ListActions() {
  const client = useQueryClient();

  async function refresh() {
    try {
      await Promise.all([client.invalidateQueries(), refreshMenuBar()]);
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't refresh sessions",
        message: String(error),
      });
    }
  }

  return (
    <ActionPanel.Section>
      <Action
        title="Refresh"
        icon={Icon.ArrowClockwise}
        shortcut={Keyboard.Shortcut.Common.Refresh}
        onAction={refresh}
      />
      <Action.OpenInBrowser
        title="Open Firmowid"
        icon={Icon.Globe}
        url={timetrackerUrl()}
      />
    </ActionPanel.Section>
  );
}
