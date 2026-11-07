import { z } from "zod";

import { listSessions } from "../lib/api";
import { authorize } from "../lib/auth";

interface Input {
  /** Number of sessions to return, from 1 to 100. Defaults to 25. */
  limit?: number;
  /** Number of sessions to skip. Defaults to 0. Increase by limit when has_more is true. */
  offset?: number;
}

export default async function tool(input: Input) {
  const { limit, offset } = z
    .object({
      limit: z.number().int().min(1).max(100).default(25),
      offset: z.number().int().min(0).default(0),
    })
    .parse(input);

  return listSessions({ token: await authorize(), limit, offset });
}
