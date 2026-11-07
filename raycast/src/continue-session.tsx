import {
  Action,
  ActionPanel,
  closeMainWindow,
  Icon,
  List,
  PopToRootType,
  showToast,
  Toast,
} from "@raycast/api";
import { withAccessToken } from "@raycast/utils";
import { useInfiniteQuery, useMutation } from "@tanstack/react-query";

import SessionItem from "./components/session-item";
import type { Session } from "./lib/api";
import { authorize } from "./lib/auth";
import { startSessionMutationOptions } from "./lib/mutations";
import { sessionHistoryOptions } from "./lib/queries";
import { withQueryClient } from "./lib/query-client";

function ContinueSession() {
  const history = useInfiniteQuery(sessionHistoryOptions);
  const start = useMutation(startSessionMutationOptions);

  async function continueSession(session: Session) {
    await closeMainWindow({
      clearRootSearch: true,
      popToRootType: PopToRootType.Immediate,
    });

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Starting session…",
    });

    try {
      await start.mutateAsync({
        session: {
          ...session,
          id: crypto.randomUUID(),
          lockdown: false,
          // oxlint-disable-next-line react/purity -- This handler runs after a user action.
          start_datetime: new Date().toISOString(),
          end_datetime: undefined,
        },
      });
      toast.style = Toast.Style.Success;
      toast.title = "Session started";
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = `Couldn't start the session: ${String(error)}`;
    }
  }

  return (
    <List
      isLoading={history.isFetching}
      searchBarPlaceholder="Search sessions to continue…"
      pagination={{
        pageSize: 25,
        hasMore: history.hasNextPage,
        onLoadMore: () => {
          void history.fetchNextPage({ cancelRefetch: false });
        },
      }}
    >
      {!history.isFetching ? (
        <List.EmptyView
          icon={history.error ? Icon.ExclamationMark : Icon.Clock}
          title={history.error ? "Couldn't load sessions" : "No sessions"}
          description={history.error?.message}
        />
      ) : null}
      {history.data?.pages.flatMap((page) =>
        page.results.map((session) => (
          <SessionItem
            key={session.id}
            session={session}
            actions={
              <ActionPanel>
                <Action
                  title="Continue Session"
                  icon={Icon.Play}
                  onAction={() => continueSession(session)}
                />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}

export default withAccessToken({ authorize })(withQueryClient(ContinueSession));
