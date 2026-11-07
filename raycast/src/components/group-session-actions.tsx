import {
  Action,
  ActionPanel,
  Alert,
  confirmAlert,
  Form,
  Icon,
  Keyboard,
  showToast,
  Toast,
  useNavigation,
} from "@raycast/api";
import { FormValidation, useForm, useFrecencySorting } from "@raycast/utils";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useRef } from "react";

import type { editSession, Project, Session } from "../lib/api";
import {
  deleteSessionGroupMutationOptions,
  editSessionGroupMutationOptions,
} from "../lib/mutations";
import { projectsOptions } from "../lib/queries";
import { withQueryClient } from "../lib/query-client";

type Group = [Session, ...Session[]];

function GroupSessionForm({ sessions }: { sessions: Group }) {
  const { pop } = useNavigation();
  const { data, isFetching } = useQuery(projectsOptions);

  const { data: projects, visitItem } = useFrecencySorting(data, {
    namespace: "projects",
  });

  const mutation = useMutation(editSessionGroupMutationOptions);
  const [first] = sessions;
  const remoteChanged = useRef(false);

  const sameRemote = sessions.every(
    (session) => session.is_remote === first.is_remote
  );

  const { handleSubmit, itemProps } = useForm<{
    title: string;
    project_id: string;
    remote: boolean;
  }>({
    initialValues: {
      title: first.title,
      project_id: first.project.id,
      remote: first.is_remote,
    },
    validation: {
      title: FormValidation.Required,
      project_id: FormValidation.Required,
    },
    async onSubmit(values) {
      const toast = await showToast({
        style: Toast.Style.Animated,
        title: "Saving sessions…",
      });

      try {
        const input: Omit<Parameters<typeof editSession>[0]["input"], "id"> = {
          title: values.title,
          project_id: values.project_id,
        };

        if (sameRemote || remoteChanged.current) {
          input.is_remote = values.remote;
        }

        await mutation.mutateAsync({
          ids: sessions.map((session) => session.id),
          input,
        });

        const project = projects.find(
          (candidate) => candidate.id === values.project_id
        );

        if (project) {
          await visitItem(project);
        }

        toast.style = Toast.Style.Success;
        toast.title = "Sessions saved";
        pop();
      } catch (error) {
        toast.style = Toast.Style.Failure;
        toast.title = "Couldn't save all sessions";
        toast.message = `Some sessions may have been updated. ${String(error)}`;
      }
    },
  });

  return (
    <Form
      navigationTitle="Edit Sessions"
      isLoading={isFetching}
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Save Sessions"
            icon={Icon.Checkmark}
            onSubmit={handleSubmit}
          />
        </ActionPanel>
      }
    >
      <Form.TextField title="Description" {...itemProps.title} />
      <Form.Dropdown title="Project" {...itemProps.project_id}>
        {projects.map((project) => (
          <Form.Dropdown.Item
            key={project.id}
            value={project.id}
            title={project.name}
          />
        ))}
      </Form.Dropdown>
      <Form.Checkbox
        label="Remote Work"
        {...itemProps.remote}
        info={
          sameRemote
            ? undefined
            : "Sessions have different values. Change this checkbox to apply one value to all."
        }
        onChange={(value) => {
          remoteChanged.current = true;
          itemProps.remote.onChange?.(value);
        }}
      />
    </Form>
  );
}

const PushedGroupSessionForm = withQueryClient(GroupSessionForm);

export default function GroupSessionActions({ sessions }: { sessions: Group }) {
  const { data, isFetching } = useQuery(projectsOptions);

  const { data: projects, visitItem } = useFrecencySorting(data, {
    namespace: "projects",
  });

  const mutation = useMutation(editSessionGroupMutationOptions);
  const remove = useMutation(deleteSessionGroupMutationOptions);

  async function changeProject(project: Project) {
    if (project.id === sessions[0].project.id) {
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Changing project…",
    });

    try {
      await mutation.mutateAsync({
        ids: sessions.map((session) => session.id),
        input: { project_id: project.id },
      });
      await visitItem(project);
      toast.style = Toast.Style.Success;
      toast.title = "Project changed";
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Couldn't change project for all sessions";
      toast.message = `Some sessions may have been updated. ${String(error)}`;
    }
  }

  async function removeSessions() {
    if (
      !(await confirmAlert({
        title: "Delete Sessions?",
        message: `Delete all ${sessions.length} sessions in this group?`,
        primaryAction: {
          title: "Delete Sessions",
          style: Alert.ActionStyle.Destructive,
        },
        dismissAction: { title: "Cancel" },
      }))
    ) {
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Deleting sessions…",
    });

    try {
      await remove.mutateAsync(sessions.map((session) => session.id));
      toast.style = Toast.Style.Success;
      toast.title = "Sessions deleted";
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Couldn't delete all sessions";
      toast.message = `Some sessions may have been deleted. ${String(error)}`;
    }
  }

  return (
    <>
      {sessions.every((session) => session.lockdown === false) ? (
        <>
          <Action.Push
            title="Edit Sessions"
            icon={Icon.Pencil}
            shortcut={Keyboard.Shortcut.Common.Edit}
            target={<PushedGroupSessionForm sessions={sessions} />}
          />
          <ActionPanel.Submenu
            title="Change Project…"
            icon={Icon.Folder}
            shortcut={{ modifiers: ["cmd", "shift"], key: "p" }}
            isLoading={isFetching}
          >
            {projects.map((project) => (
              <Action
                key={project.id}
                title={project.name}
                autoFocus={project.id === sessions[0].project.id}
                onAction={() => changeProject(project)}
              />
            ))}
          </ActionPanel.Submenu>
        </>
      ) : null}
      <Action.CopyToClipboard
        title="Copy Session Title"
        content={sessions[0].title}
        shortcut={Keyboard.Shortcut.Common.Copy}
      />
      <Action
        title="Delete Sessions"
        icon={Icon.Trash}
        style={Action.Style.Destructive}
        shortcut={Keyboard.Shortcut.Common.Remove}
        onAction={removeSessions}
      />
    </>
  );
}
