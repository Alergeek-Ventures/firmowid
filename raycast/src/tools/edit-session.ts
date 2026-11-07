import { z } from "zod";

import { editSession } from "../lib/api";
import { authorize } from "../lib/auth";
import { refreshMenuBar } from "../lib/status";

interface Input {
  /** Session UUID from Get Current Session or List Sessions. */
  id: string;
  /** New description. Omit to keep the current description. */
  title?: string;
  /** New project UUID from List Projects. Omit to keep the current project. */
  projectId?: string;
  /** Whether the work is remote. Omit to keep the current setting. */
  isRemote?: boolean;
  /** New start time in UTC ISO 8601 format, for example 2026-10-25T09:00:00Z. */
  startDatetime?: string;
  /** New end time in UTC ISO 8601 format. Setting this ends a running session. Omit to keep it running. */
  endDatetime?: string;
}

export default async function tool(input: Input) {
  const { id, title, projectId, isRemote, startDatetime, endDatetime } = z
    .object({
      id: z.uuid(),
      title: z
        .string()
        .refine((value) => value.trim().length > 0, "Enter a description.")
        .optional(),
      projectId: z.uuid().optional(),
      isRemote: z.boolean().optional(),
      startDatetime: z.iso.datetime().optional(),
      endDatetime: z.iso.datetime().optional(),
    })
    .refine(
      (changes) =>
        Object.entries(changes).some(
          ([key, value]) => key !== "id" && value !== undefined
        ),
      "Provide at least one field to update."
    )
    .parse(input);

  const result = await editSession({
    token: await authorize(),
    input: {
      id,
      title,
      project_id: projectId,
      is_remote: isRemote,
      start_datetime: startDatetime,
      end_datetime: endDatetime,
    },
  });

  await refreshMenuBar();

  return result;
}
