import { Icon, List } from "@raycast/api";
import { withAccessToken } from "@raycast/utils";
import { useIsRestoring, useQuery } from "@tanstack/react-query";

import SessionForm from "./components/session-form";
import { authorize } from "./lib/auth";
import { currentSessionOptions } from "./lib/queries";
import { withQueryClient } from "./lib/query-client";

function EditCurrentSession() {
  const isRestoring = useIsRestoring();

  return isRestoring ? <List isLoading /> : <CurrentSessionForm />;
}

function CurrentSessionForm() {
  const current = useQuery(currentSessionOptions);

  if (current.isFetchedAfterMount && current.data && !current.error) {
    return (
      <SessionForm
        key={current.data.id}
        kind="edit"
        session={current.data}
        navigationTitle="Edit Current Session"
        returnToRoot
      />
    );
  }

  return (
    <List isLoading={!current.isFetchedAfterMount || current.isFetching}>
      {current.isFetchedAfterMount && !current.isFetching ? (
        <List.EmptyView
          icon={current.error ? Icon.ExclamationMark : Icon.Pause}
          title={current.error ? "Couldn't load sessions" : "No active session"}
          description={current.error?.message}
        />
      ) : null}
    </List>
  );
}

export default withAccessToken({ authorize })(
  withQueryClient(EditCurrentSession)
);
