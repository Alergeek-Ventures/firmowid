import type { LaunchProps } from "@raycast/api";
import {
  Action,
  ActionPanel,
  closeMainWindow,
  Icon,
  Keyboard,
  List,
} from "@raycast/api";
import { withAccessToken } from "@raycast/utils";
import {
  useInfiniteQuery,
  usePrefetchQuery,
  useQuery,
} from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";

import ListActions from "./components/list-actions";
import SessionForm from "./components/session-form";
import SessionItem from "./components/session-item";
import type { Session } from "./lib/api";
import { authorize } from "./lib/auth";
import {
  currentSessionOptions,
  projectsOptions,
  sessionHistoryOptions,
} from "./lib/queries";
import { withQueryClient } from "./lib/query-client";
import { formatDuration } from "./lib/status";

const dayFormatter = new Intl.RelativeTimeFormat("en-US", { numeric: "auto" });

export interface SessionsLaunchContext {
  editSession: Session;
}

function SessionsCommand({
  launchContext,
}: LaunchProps<{ launchContext: SessionsLaunchContext }>) {
  return launchContext?.editSession ? (
    <SessionForm
      kind="edit"
      session={launchContext.editSession}
      navigationTitle="Edit Session"
      onSaved={closeMainWindow}
    />
  ) : (
    <Sessions />
  );
}

function Sessions() {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), 60_000);

    return () => clearInterval(interval);
  }, []);
  const overview = useQuery(currentSessionOptions);
  const history = useInfiniteQuery(sessionHistoryOptions);
  usePrefetchQuery(projectsOptions);
  const current = overview.data;

  const error = overview.error ?? history.error;

  const historyDays = useMemo(
    () =>
      history.data?.pages
        .flatMap((page) => page.results)
        .reduce<
          { day: number; sessions: Session[]; totalMilliseconds: number }[]
        >((days, session) => {
          if (session.id === current?.id) {
            return days;
          }
          const day = new Date(session.start_datetime).setHours(0, 0, 0, 0);
          let group = days.at(-1);

          if (group?.day !== day) {
            group = { day, sessions: [], totalMilliseconds: 0 };
            days.push(group);
          }

          group.sessions.push(session);
          group.totalMilliseconds +=
            (session.end_datetime ? Date.parse(session.end_datetime) : now) -
            Date.parse(session.start_datetime);

          return days;
        }, []),
    [history.data, current?.id, now]
  );

  const today = new Date(now).setHours(0, 0, 0, 0);

  return (
    <List
      isLoading={overview.isLoading || history.isLoading}
      searchBarPlaceholder="Search sessions…"
      pagination={{
        pageSize: 25,
        hasMore: history.hasNextPage,
        onLoadMore: () => {
          void history.fetchNextPage({ cancelRefetch: false });
        },
      }}
      actions={
        <ActionPanel>
          <ListActions />
        </ActionPanel>
      }
    >
      {error ? (
        <List.EmptyView
          icon={Icon.ExclamationMark}
          title="Couldn't load sessions"
          description={error.message}
          actions={
            <ActionPanel>
              <ListActions />
            </ActionPanel>
          }
        />
      ) : (
        <>
          <List.Section title="Current Session">
            {current ? (
              <SessionItem session={current} />
            ) : current === null ? (
              <List.Item
                title="No active session"
                subtitle="Start a session in a project to track your work"
                icon={Icon.Pause}
                actions={
                  <ActionPanel>
                    <Action.Push
                      title="Start Session"
                      icon={Icon.Play}
                      shortcut={Keyboard.Shortcut.Common.New}
                      target={
                        <SessionForm
                          kind="start"
                          navigationTitle="Start Session"
                          onStart={closeMainWindow}
                        />
                      }
                    />
                    <ListActions />
                  </ActionPanel>
                }
              />
            ) : null}
          </List.Section>
          {historyDays?.map(({ day, sessions, totalMilliseconds }) => (
            <List.Section
              key={day}
              title={dayFormatter
                .format(
                  Math.round((day - today) / (24 * 60 * 60 * 1000)),
                  "day"
                )
                .replace(/^./, (letter) => letter.toUpperCase())}
              subtitle={formatDuration(totalMilliseconds)}
            >
              {sessions.map((session) => (
                <SessionItem key={session.id} session={session} />
              ))}
            </List.Section>
          ))}
        </>
      )}
    </List>
  );
}

export default withAccessToken({ authorize })(withQueryClient(SessionsCommand));
