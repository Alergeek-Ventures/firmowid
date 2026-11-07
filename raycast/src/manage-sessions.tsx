import type { LaunchProps } from "@raycast/api";
import { Action, ActionPanel, Color, Icon, Keyboard, List } from "@raycast/api";
import { withAccessToken } from "@raycast/utils";
import {
  useInfiniteQuery,
  usePrefetchQuery,
  useQuery,
} from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";

import GroupSessionActions from "./components/group-session-actions";
import ListActions from "./components/list-actions";
import SessionForm, { PushedSessionForm } from "./components/session-form";
import SessionItem, {
  SessionDeleteAction,
  SessionEditAction,
  SessionPrimaryAction,
} from "./components/session-item";
import type { Session } from "./lib/api";
import { authorize } from "./lib/auth";
import {
  currentSessionOptions,
  projectsOptions,
  sessionHistoryOptions,
} from "./lib/queries";
import { withQueryClient } from "./lib/query-client";
import { formatDuration } from "./lib/status";

const weekdayFormatter = new Intl.DateTimeFormat("en-US", { weekday: "long" });

const dateFormatter = new Intl.DateTimeFormat("pl-PL", {
  day: "2-digit",
  month: "2-digit",
});

const dateWithYearFormatter = new Intl.DateTimeFormat("pl-PL", {
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

function formatDay(day: number, currentYear: number): string {
  const weekday = weekdayFormatter
    .format(day)
    .replace(/^./u, (letter) => letter.toUpperCase());

  const formatter =
    new Date(day).getFullYear() === currentYear
      ? dateFormatter
      : dateWithYearFormatter;

  return `${weekday} (${formatter.format(day)})`;
}

function groupSessions(sessions: Session[]): [Session, ...Session[]][] {
  const groups: [Session, ...Session[]][] = [];

  for (const session of sessions) {
    const group = groups.at(-1);

    if (
      group &&
      group[0].title === session.title &&
      group[0].project.id === session.project.id &&
      new Date(group[0].start_datetime).toDateString() ===
        new Date(session.start_datetime).toDateString()
    ) {
      group.push(session);
    } else {
      groups.push([session]);
    }
  }

  return groups;
}

function GroupSessionsList({
  sessions,
}: {
  sessions: [Session, ...Session[]];
}) {
  const { data: current } = useQuery(currentSessionOptions);
  const { data: history } = useInfiniteQuery(sessionHistoryOptions);
  const availableSessions = history?.pages.flatMap((page) => page.results);

  return (
    <List navigationTitle={sessions[0].title}>
      {sessions.map((session) => {
        const updated =
          current?.id === session.id
            ? current
            : (availableSessions?.find((item) => item.id === session.id) ??
              (availableSessions ? undefined : session));

        return updated ? (
          <SessionItem
            key={updated.id}
            session={updated}
            showTime
            actions={
              <ActionPanel>
                <SessionEditAction session={updated} />
                <SessionDeleteAction session={updated} />
              </ActionPanel>
            }
          />
        ) : null;
      })}
    </List>
  );
}

const PushedGroupSessionsList = withQueryClient(GroupSessionsList);

function SessionGroup({
  sessions,
  now,
}: {
  sessions: [Session, ...Session[]];
  now: number;
}) {
  const [first] = sessions;

  if (sessions.length === 1) {
    return <SessionItem session={first} />;
  }

  const active = sessions.some((session) => !session.end_datetime);
  let total = 0;

  for (const session of sessions) {
    total +=
      (session.end_datetime ? Date.parse(session.end_datetime) : now) -
      Date.parse(session.start_datetime);
  }

  return (
    <List.Item
      title={first.title}
      subtitle={first.project.name}
      keywords={[first.project.name]}
      icon={{
        source: active ? Icon.Play : Icon.CheckCircle,
        tintColor: active ? Color.Green : Color.SecondaryText,
      }}
      accessories={[
        { text: `${sessions.length} sessions` },
        { text: formatDuration(total), tooltip: "Duration" },
      ]}
      actions={
        <ActionPanel>
          <SessionPrimaryAction session={first} />
          <GroupSessionActions sessions={sessions} />
          <Action.Push
            title="Show Sessions"
            icon={Icon.List}
            shortcut={Keyboard.Shortcut.Common.Open}
            target={<PushedGroupSessionsList sessions={sessions} />}
          />
          <ListActions />
        </ActionPanel>
      }
    />
  );
}

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
      returnToRoot
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

  const historyDays = useMemo(() => {
    if (!history.data) {
      return;
    }

    const days: {
      day: number;
      sessions: Session[];
      totalMilliseconds: number;
    }[] = [];

    for (const session of history.data.pages.flatMap((page) => page.results)) {
      if (session.id === current?.id) {
        continue;
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
    }

    return days;
  }, [history.data, current?.id, now]);

  const currentYear = new Date(now).getFullYear();
  const today = new Date(now).setHours(0, 0, 0, 0);
  const todayHistory = historyDays?.find(({ day }) => day === today);

  const todaySessions = current
    ? [current, ...(todayHistory?.sessions ?? [])]
    : (todayHistory?.sessions ?? []);

  const todayDuration =
    (todayHistory?.totalMilliseconds ?? 0) +
    (current ? now - Math.max(today, Date.parse(current.start_datetime)) : 0);

  return (
    <List
      isLoading={overview.isFetching || history.isFetching}
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
      {error && overview.data === undefined && history.data === undefined ? (
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
          <List.Section title="Today" subtitle={formatDuration(todayDuration)}>
            {current === null ? (
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
                        <PushedSessionForm
                          kind="start"
                          navigationTitle="Start Session"
                          returnToRoot
                        />
                      }
                    />
                    <ListActions />
                  </ActionPanel>
                }
              />
            ) : null}
            {groupSessions(todaySessions).map((sessions) => (
              <SessionGroup
                key={sessions[0].id}
                sessions={sessions}
                now={now}
              />
            ))}
          </List.Section>
          {historyDays
            ?.filter(({ day }) => day !== today)
            .map(({ day, sessions, totalMilliseconds }) => (
              <List.Section
                key={day}
                title={formatDay(day, currentYear)}
                subtitle={formatDuration(totalMilliseconds)}
              >
                {groupSessions(sessions).map((group) => (
                  <SessionGroup key={group[0].id} sessions={group} now={now} />
                ))}
              </List.Section>
            ))}
        </>
      )}
    </List>
  );
}

export default withAccessToken({ authorize })(withQueryClient(SessionsCommand));
