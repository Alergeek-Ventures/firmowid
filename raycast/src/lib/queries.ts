import {
  infiniteQueryOptions,
  queryOptions,
  skipToken,
} from "@tanstack/react-query";

import type { Session } from "./api";
import { getCurrentSession, listProjects, listSessions } from "./api";
import { AuthenticationError, getBackgroundAccessToken } from "./auth";

export async function accessToken() {
  const token = await getBackgroundAccessToken();

  if (!token) {
    throw new AuthenticationError();
  }

  return token;
}

export const currentSessionOptions = queryOptions<Session | null>({
  queryKey: ["sessions", "current"],
  queryFn: async ({ signal }) =>
    (await getCurrentSession({ token: await accessToken(), signal })) ?? null,
  meta: { errorToastTitle: "Couldn't load Firmowid data" },
});

export const projectsOptions = queryOptions({
  queryKey: ["projects"],
  queryFn: async ({ signal }) =>
    listProjects({ token: await accessToken(), signal }),
  meta: { errorToastTitle: "Couldn't load Firmowid data" },
});

export function sessionNeighborsOptions(session?: Session) {
  return queryOptions({
    queryKey: [
      "sessions",
      "neighbors",
      session?.id,
      session?.start_datetime,
      session?.end_datetime,
    ],
    queryFn: session
      ? async ({ signal }) => {
          const options = {
            token: await accessToken(),
            signal,
            limit: 1,
          };

          const [previous, next] = await Promise.all([
            listSessions({
              ...options,
              filter: {
                id: { not_eq: session.id },
                end_datetime: { less_than_or_equal: session.start_datetime },
              },
              sort: "-end_datetime,-start_datetime",
            }),
            listSessions({
              ...options,
              filter: {
                id: { not_eq: session.id },
                start_datetime: {
                  greater_than_or_equal:
                    session.end_datetime ?? session.start_datetime,
                },
              },
              sort: "start_datetime,end_datetime",
            }),
          ]);

          return {
            previous: previous.results[0] ?? null,
            next: next.results[0] ?? null,
          };
        }
      : skipToken,
    meta: { errorToastTitle: "Couldn't load neighboring sessions" },
  });
}

export const sessionHistoryOptions = infiniteQueryOptions({
  queryKey: ["sessions", "history", "keyset"],
  queryFn: async ({
    signal,
    pageParam,
  }: {
    signal: AbortSignal;
    pageParam: string | null;
  }) =>
    listSessions({
      token: await accessToken(),
      signal,
      limit: 50,
      after: pageParam ?? undefined,
    }),
  initialPageParam: null,
  getNextPageParam: (lastPage) => lastPage.next_cursor,
  meta: { errorToastTitle: "Couldn't load session history" },
});
