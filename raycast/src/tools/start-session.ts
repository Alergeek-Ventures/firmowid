import { z } from "zod";

import { startSession } from "../lib/api";
import { authorize } from "../lib/auth";
import { refreshMenuBar } from "../lib/status";

interface Input {
  /** Description of the work to track. */
  title: string;
  /** Project UUID from List Projects, Get Current Session, or List Sessions. */
  projectId: string;
  /** Whether the work is remote. Defaults to false. Preserve this when continuing a session. */
  isRemote?: boolean;
}

export default async function tool(input: Input) {
  const { title, projectId, isRemote } = z
    .object({
      title: z
        .string()
        .refine((value) => value.trim().length > 0, "Enter a description."),
      projectId: z.uuid(),
      isRemote: z.boolean().default(false),
    })
    .parse(input);

  const token = await authorize();

  try {
    return await startSession({
      token,
      input: { title, project_id: projectId, is_remote: isRemote },
    });
  } finally {
    await refreshMenuBar();
  }
}
