import { environment } from "@raycast/api";
import { mutationOptions } from "@tanstack/react-query";
import type {
  MutationFunctionContext,
  QueryClient,
} from "@tanstack/react-query";

import type { Session } from "./api";
import {
  deleteSession,
  editSession,
  startSession,
  stopCurrentSession,
} from "./api";
import {
  accessToken,
  currentSessionOptions,
  sessionHistoryOptions,
} from "./queries";
import { refreshMenuBar } from "./status";

async function snapshotSessions({ client }: MutationFunctionContext) {
  await client.cancelQueries({ queryKey: ["sessions"] });
  client.getQueryCache().build<Session | null>(client, currentSessionOptions);

  return {
    current: client.getQueryData(currentSessionOptions.queryKey),
    history: client.getQueryData(sessionHistoryOptions.queryKey),
  };
}

function updateHistory(client: QueryClient, sessions: Session[]) {
  client.setQueryData(sessionHistoryOptions.queryKey, (previous) => {
    if (!previous) {
      return previous;
    }

    const added = sessions.filter(
      (session) =>
        !previous.pages.some((page) =>
          page.results.some((item) => item.id === session.id)
        )
    );

    return {
      ...previous,
      pages: previous.pages.map((page, index) => ({
        ...page,
        results: [
          ...(index === 0 ? added : []),
          ...page.results.map(
            (item) => sessions.find((session) => session.id === item.id) ?? item
          ),
        ],
      })),
    };
  });
}

function rollback(
  previous: Awaited<ReturnType<typeof snapshotSessions>> | undefined,
  { client }: MutationFunctionContext
) {
  if (!previous) {
    return;
  }

  if (previous.current === undefined) {
    if (client.getQueryData(currentSessionOptions.queryKey) !== undefined) {
      client.removeQueries({
        queryKey: currentSessionOptions.queryKey,
        exact: true,
      });
    }
  } else {
    client.setQueryData(currentSessionOptions.queryKey, previous.current);
  }

  client.setQueryData(sessionHistoryOptions.queryKey, previous.history);
}

async function refreshSessions({ client }: MutationFunctionContext) {
  await client.invalidateQueries({ queryKey: ["sessions"] });

  if (environment.entryPointMode !== "menu-bar") {
    await refreshMenuBar();
  }
}

function sessionMutationOptions<T, TResult>(
  mutationFn: (variables: T) => Promise<TResult>,
  update: (
    variables: T,
    previous: Awaited<ReturnType<typeof snapshotSessions>>,
    client: QueryClient
  ) => void
) {
  return mutationOptions({
    mutationKey: ["sessions"],
    mutationFn,
    async onMutate(variables, context) {
      const previous = await snapshotSessions(context);
      update(variables, previous, context.client);

      return previous;
    },
    onError(_error, _variables, previous, context) {
      rollback(previous, context);
    },
    onSettled(_data, _error, _variables, _previous, context) {
      return refreshSessions(context);
    },
  });
}

export const startSessionMutationOptions = sessionMutationOptions(
  async ({ session }: { session: Session }) =>
    startSession({
      token: await accessToken(),
      input: {
        title: session.title,
        project_id: session.project.id,
        is_remote: session.is_remote,
      },
    }),
  ({ session }, { current }, client) => {
    client.setQueryData(currentSessionOptions.queryKey, session);
    updateHistory(
      client,
      current
        ? [session, { ...current, end_datetime: session.start_datetime }]
        : [session]
    );
  }
);

export const stopSessionMutationOptions = sessionMutationOptions<
  void,
  Awaited<ReturnType<typeof stopCurrentSession>>
>(
  async () => stopCurrentSession({ token: await accessToken() }),
  (_variables, { current }, client) => {
    client.setQueryData(currentSessionOptions.queryKey, null);

    if (current) {
      updateHistory(client, [
        { ...current, end_datetime: new Date().toISOString() },
      ]);
    }
  }
);

export const deleteSessionMutationOptions = sessionMutationOptions(
  async ({ session }: { session: Session }) =>
    deleteSession({ token: await accessToken(), id: session.id }),
  ({ session }, _previous, client) => {
    client.setQueryData(currentSessionOptions.queryKey, (current) =>
      current?.id === session.id ? null : current
    );
    client.setQueryData(
      sessionHistoryOptions.queryKey,
      (history) =>
        history && {
          ...history,
          pages: history.pages.map((page) => ({
            ...page,
            results: page.results.filter((item) => item.id !== session.id),
          })),
        }
    );
  }
);

export const editSessionMutationOptions = sessionMutationOptions(
  async ({
    input,
  }: {
    session: Session;
    input: Parameters<typeof editSession>[0]["input"];
  }) => editSession({ token: await accessToken(), input }),
  ({ session }, _previous, client) => {
    client.setQueryData(currentSessionOptions.queryKey, (current) =>
      !session.end_datetime
        ? session
        : current?.id === session.id
          ? null
          : current
    );
    updateHistory(client, [session]);
  }
);
