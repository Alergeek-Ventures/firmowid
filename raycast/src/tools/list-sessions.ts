import { z } from "zod";

import { listSessions } from "../lib/api";
import { authorize } from "../lib/auth";

interface Input {
  /** Number of sessions to return, from 1 to 100. Defaults to 25. */
  limit?: number;
  /** Cursor returned as next_cursor by the previous page. Omit for the first page. */
  after?: string;
}

export default async function tool(input: Input) {
  const { limit, after } = z
    .object({
      limit: z.number().int().min(1).max(100).default(25),
      after: z.string().min(1).optional(),
    })
    .parse(input);

  return listSessions({ token: await authorize(), limit, after });
}
