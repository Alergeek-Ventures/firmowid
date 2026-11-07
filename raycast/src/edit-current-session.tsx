import { closeMainWindow, Icon, List } from "@raycast/api";
import { withAccessToken } from "@raycast/utils";
import { useQuery } from "@tanstack/react-query";

import SessionForm from "./components/session-form";
import { authorize } from "./lib/auth";
import { currentSessionOptions } from "./lib/queries";
import { withQueryClient } from "./lib/query-client";

function EditCurrentSession() {
  const current = useQuery(currentSessionOptions);

  if (current.data && !current.error) {
    return (
      <SessionForm
        kind="edit"
        session={current.data}
        navigationTitle="Edit Current Session"
        onSaved={closeMainWindow}
      />
    );
  }

  return (
    <List isLoading={current.isPending || current.isFetching}>
      {!current.isPending && !current.isFetching ? (
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
