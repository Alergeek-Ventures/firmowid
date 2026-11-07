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

export const confirmation: Tool.Confirmation<Input> = async ({ id }) => ({
  style: Action.Style.Destructive,
  message: "Delete this session permanently?",
  info: [{ name: "Session ID", value: id }],
});

export default async function tool(input: Input) {
  const id = z.uuid().parse(input.id);
  await deleteSession({ token: await authorize(), id });
  await refreshMenuBar();

  return { deleted: true, id };
}
