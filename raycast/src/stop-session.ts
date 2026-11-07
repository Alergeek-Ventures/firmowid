import { showToast, Toast } from "@raycast/api";
import { withAccessToken } from "@raycast/utils";

import { stopCurrentSession } from "./lib/api";
import { authorize } from "./lib/auth";
import { refreshMenuBar } from "./lib/status";

async function StopSession() {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Stopping session…",
  });

  try {
    await stopCurrentSession({ token: await authorize() });
    await refreshMenuBar();
    toast.style = Toast.Style.Success;
    toast.title = "Session stopped";
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = `Couldn't stop the session: ${String(error)}`;
  }
}

export default withAccessToken({ authorize })(StopSession);
