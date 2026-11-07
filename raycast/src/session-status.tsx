import {
  Color,
  Icon,
  showToast,
  Toast,
  launchCommand,
  LaunchType,
  MenuBarExtra,
} from "@raycast/api";
import {
  useIsFetching,
  useIsRestoring,
  useMutation,
  usePrefetchQuery,
  useQuery,
} from "@tanstack/react-query";

import ProjectSubmenu from "./components/project-submenu";
import { AuthenticationError } from "./lib/auth";
import { stopSessionMutationOptions } from "./lib/mutations";
import { currentSessionOptions, projectsOptions } from "./lib/queries";
import { withQueryClient } from "./lib/query-client";
import { duration, timetrackerUrl } from "./lib/status";
import type { SessionsLaunchContext } from "./manage-sessions";

function SessionStatus() {
  const {
    data: current,
    dataUpdatedAt,
    error,
    errorUpdatedAt,
    isFetching,
  } = useQuery(currentSessionOptions);

  const isRestoring = useIsRestoring();
  usePrefetchQuery(projectsOptions);

  const fetchingProjects = useIsFetching({
    queryKey: projectsOptions.queryKey,
  });

  const mutation = useMutation(stopSessionMutationOptions);

  const shortTitle = !current?.title
    ? ""
    : current.title.length > 24
      ? `${current.title.slice(0, 23)}…`
      : current.title;

  const title = current ? `${duration(current)} · ${shortTitle}` : "";

  async function stopSession() {
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Stopping session…",
    });

    try {
      await mutation.mutateAsync();
      toast.style = Toast.Style.Success;
      toast.title = "Session stopped";
    } catch (mutationError) {
      toast.style = Toast.Style.Failure;
      toast.title = `Couldn't stop the session: ${String(mutationError)}`;
    }
  }

  if (!current && (isRestoring || isFetching)) {
    return (
      <MenuBarExtra
        isLoading
        icon={{ source: Icon.Play, tintColor: Color.Green }}
      />
    );
  }

  if (
    !current ||
    error instanceof AuthenticationError ||
    (error &&
      !isRestoring &&
      !isFetching &&
      errorUpdatedAt - dataUpdatedAt >= 5 * 60_000)
  ) {
    return null;
  }

  return (
    <MenuBarExtra
      isLoading={isRestoring || isFetching || fetchingProjects > 0}
      icon={{
        source: Icon.Play,
        tintColor: Color.Green,
      }}
      title={title}
      tooltip={`${current.title} · ${current.project.name}`}
    >
      <MenuBarExtra.Section title={current.project.name}>
        <MenuBarExtra.Item title={current.title} />
        {current.lockdown === false ? (
          <>
            <ProjectSubmenu session={current} />
            <MenuBarExtra.Item
              title="Edit Session"
              icon={Icon.Pencil}
              onAction={() =>
                launchCommand({
                  name: "manage-sessions",
                  type: LaunchType.UserInitiated,
                  context: {
                    editSession: current,
                  } satisfies SessionsLaunchContext,
                })
              }
            />
          </>
        ) : null}
        <MenuBarExtra.Item
          title="Stop Session"
          icon={Icon.Stop}
          onAction={stopSession}
        />
      </MenuBarExtra.Section>
      <MenuBarExtra.Item
        title="Manage Sessions"
        icon={Icon.List}
        onAction={() =>
          launchCommand({
            name: "manage-sessions",
            type: LaunchType.UserInitiated,
          })
        }
      />
      <MenuBarExtra.Item
        title="Open Firmowid"
        icon={Icon.Globe}
        onAction={() => open(timetrackerUrl())}
      />
    </MenuBarExtra>
  );
}

export default withQueryClient(SessionStatus);
