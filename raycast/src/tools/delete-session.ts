import type { Tool } from "@raycast/api";
import { Action } from "@raycast/api";
import { z } from "zod";

import { deleteSession } from "../lib/api";
import { authorize } from "../lib/auth";
import { refreshMenuBar } from "../lib/status";

interface Input {
  /** Session UUID from Get Current Session or List Sessions. */
  id: string;
}

export function confirmation({
  id,
}: Input): ReturnType<Tool.Confirmation<Input>> {
  return Promise.resolve({
    style: Action.Style.Destructive,
    message: "Delete this session permanently?",
    info: [{ name: "Session ID", value: id }],
  });
}

export default async function tool(input: Input) {
  const id = z.uuid().parse(input.id);
  await deleteSession({ token: await authorize(), id });
  await refreshMenuBar();

  return { deleted: true, id };
}
