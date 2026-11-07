import { stopCurrentSession } from "../lib/api";
import { authorize } from "../lib/auth";
import { refreshMenuBar } from "../lib/status";

export default async function tool() {
  await stopCurrentSession({ token: await authorize() });
  await refreshMenuBar();

  return { stopped: true };
}
