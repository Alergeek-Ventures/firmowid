import {
  Action,
  ActionPanel,
  Alert,
  Color,
  closeMainWindow,
  confirmAlert,
  Icon,
  showToast,
  Toast,
  Keyboard,
  List,
} from "@raycast/api";
import { useFrecencySorting } from "@raycast/utils";
import { useMutation, useQuery } from "@tanstack/react-query";

import type { Project, Session } from "../lib/api";
import {
  startSessionMutationOptions,
  stopSessionMutationOptions,
  deleteSessionMutationOptions,
  editSessionMutationOptions,
} from "../lib/mutations";
import { currentSessionOptions, projectsOptions } from "../lib/queries";
import { duration } from "../lib/status";
import ListActions from "./list-actions";
import SessionForm from "./session-form";

export default function SessionItem({
  session,
  actions,
}: {
  session: Session;
  actions?: List.Item.Props["actions"];
}) {
  return (
    <List.Item
      id={session.id}
      title={session.title}
      subtitle={session.project.name}
      keywords={[session.project.name]}
      icon={{
        source: session.end_datetime ? Icon.CheckCircle : Icon.Play,
        tintColor: session.end_datetime ? Color.SecondaryText : Color.Green,
      }}
      accessories={[
        { text: duration(session), tooltip: "Duration" },
        // { date: new Date(session.start_datetime), tooltip: "Start Time" },
      ]}
      actions={
        actions ?? (
          <ActionPanel>
            <SessionActions session={session} />
            <ListActions />
          </ActionPanel>
        )
      }
    />
  );
}

function SessionActions({ session }: { session: Session }) {
  const { data: current } = useQuery(currentSessionOptions);

  const stop = useMutation(stopSessionMutationOptions);

  const start = useMutation(startSessionMutationOptions);

  const remove = useMutation(deleteSessionMutationOptions);

  async function stopSession() {
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Stopping session…",
    });

    try {
      await stop.mutateAsync(undefined);
      toast.style = Toast.Style.Success;
      toast.title = "Session stopped";
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = `Couldn't stop the session: ${String(error)}`;
    }
  }

  async function continueSession() {
    await closeMainWindow();

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Starting session…",
    });

    try {
      await start.mutateAsync({
        session: {
          ...session,
          lockdown: false,
          id: crypto.randomUUID(),
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

  async function removeSession() {
    if (
      !(await confirmAlert({
        title: "Delete Session?",
        message: session.title,
        primaryAction: {
          title: "Delete Session",
          style: Alert.ActionStyle.Destructive,
        },
        dismissAction: { title: "Cancel" },
      }))
    ) {
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Deleting session…",
    });

    try {
      await remove.mutateAsync({ session });
      toast.style = Toast.Style.Success;
      toast.title = "Session deleted";
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = `Couldn't delete the session: ${String(error)}`;
    }
  }

  return (
    <>
      {current?.id === session.id ? (
        <Action title="Stop Session" icon={Icon.Stop} onAction={stopSession} />
      ) : (
        <Action
          title="Continue Session"
          icon={Icon.Play}
          onAction={continueSession}
        />
      )}
      {session.lockdown === false ? (
        <>
          <Action.Push
            title="Edit Session"
            icon={Icon.Pencil}
            shortcut={Keyboard.Shortcut.Common.Edit}
            target={
              <SessionForm
                kind="edit"
                session={session}
                navigationTitle="Edit Session"
              />
            }
          />
          <ProjectMenu session={session} />
        </>
      ) : null}
      <Action.CopyToClipboard
        title="Copy Session Title"
        content={session.title}
        shortcut={Keyboard.Shortcut.Common.Copy}
      />
      <Action
        title="Delete Session"
        icon={Icon.Trash}
        style={Action.Style.Destructive}
        shortcut={Keyboard.Shortcut.Common.Remove}
        onAction={removeSession}
      />
    </>
  );
}

function ProjectMenu({ session }: { session: Session }) {
  const { data, isLoading } = useQuery(projectsOptions);

  const mutation = useMutation(editSessionMutationOptions);

  const { data: projects, visitItem } = useFrecencySorting(data, {
    namespace: "projects",
  });

  async function changeProject(project: Project) {
    if (project.id === session.project.id) {
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Changing project…",
    });

    try {
      await mutation.mutateAsync({
        session: { ...session, project },
        input: { id: session.id, project_id: project.id },
      });
      toast.style = Toast.Style.Success;
      toast.title = "Project changed";
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = `Couldn't change the project: ${String(error)}`;
    }

    await visitItem(project);
  }

  return (
    <ActionPanel.Submenu
      title="Change Project…"
      icon={Icon.Folder}
      shortcut={{ modifiers: ["cmd", "shift"], key: "p" }}
      isLoading={isLoading}
    >
      {projects.map((project) => (
        <Action
          key={project.id}
          title={project.name}
          icon={Icon.Folder}
          autoFocus={project.id === session.project.id}
          onAction={() => changeProject(project)}
        />
      ))}
    </ActionPanel.Submenu>
  );
}
