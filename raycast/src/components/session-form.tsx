import {
  Action,
  ActionPanel,
  closeMainWindow,
  Form,
  Icon,
  List,
  PopToRootType,
  showToast,
  Toast,
  useNavigation,
} from "@raycast/api";
import { FormValidation, useForm, useFrecencySorting } from "@raycast/utils";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useState } from "react";

import type { Session } from "../lib/api";
import {
  startSessionMutationOptions,
  editSessionMutationOptions,
} from "../lib/mutations";
import { projectsOptions, sessionNeighborsOptions } from "../lib/queries";
import { withQueryClient } from "../lib/query-client";

type SessionFormProps = {
  navigationTitle?: string;
} & (
  | { kind: "start"; returnToRoot?: boolean }
  | { kind: "edit"; session: Session; returnToRoot?: boolean }
);

function SessionForm(props: SessionFormProps) {
  const { pop } = useNavigation();
  const { data, error, isFetching } = useQuery(projectsOptions);

  const start = useMutation(startSessionMutationOptions);

  const edit = useMutation(editSessionMutationOptions);

  const session = props.kind === "edit" ? props.session : undefined;
  // A new session starts when the form opens; re-renders must not move that time.
  // The time never changes, so there is no setter.
  // oxlint-disable-next-line react/hook-use-state
  const [openedAt] = useState(() => new Date());

  const {
    data: neighbors,
    error: neighborsError,
    isFetching: isFetchingNeighbors,
  } = useQuery(sessionNeighborsOptions(session));

  const { data: projects, visitItem } = useFrecencySorting(data, {
    namespace: "projects",
  });

  const { handleSubmit, itemProps, values } = useForm<{
    title: string;
    project_id: string;
    is_remote: boolean;
    start_datetime: Date | null;
    end_datetime: Date | null;
  }>({
    initialValues: {
      title: session?.title ?? "",
      project_id: session?.project.id ?? projects[0]?.id ?? undefined,
      is_remote: session?.is_remote ?? false,
      start_datetime: session ? new Date(session.start_datetime) : openedAt,
      end_datetime: session?.end_datetime
        ? new Date(session.end_datetime)
        : null,
    },
    validation: {
      title: FormValidation.Required,
      project_id: FormValidation.Required,
      start_datetime: FormValidation.Required,
      end_datetime: session?.end_datetime ? FormValidation.Required : undefined,
    },
    async onSubmit(submittedValues) {
      let toast: Toast | undefined;

      try {
        const input = {
          title: submittedValues.title,
          project_id: submittedValues.project_id,
          is_remote: submittedValues.is_remote,
        };

        const project = projects.find(
          (candidate) => candidate.id === submittedValues.project_id
        );

        if (!project) {
          // oxlint-disable-next-line react/todo -- This throw runs in a submit handler, not during rendering.
          throw new Error(
            "Select a project. If no projects are listed, ask your administrator for access."
          );
        }

        const optimisticSession: Session = {
          id: session?.id ?? crypto.randomUUID(),
          title: input.title,
          is_remote: input.is_remote,
          lockdown: session?.lockdown ?? false,
          project,
          start_datetime:
            submittedValues.start_datetime?.toISOString() ??
            session?.start_datetime ??
            new Date().toISOString(),
          end_datetime: submittedValues.end_datetime?.toISOString(),
        };

        if (props.returnToRoot) {
          await closeMainWindow({
            clearRootSearch: true,
            popToRootType: PopToRootType.Immediate,
          });
        }

        toast = await showToast({
          style: Toast.Style.Animated,
          title: session ? "Saving session…" : "Starting session…",
        });

        if (session) {
          await edit.mutateAsync({
            session: optimisticSession,
            input: {
              ...input,
              id: session.id,
              start_datetime: submittedValues.start_datetime?.toISOString(),
              end_datetime: submittedValues.end_datetime?.toISOString(),
            },
          });
        } else {
          await start.mutateAsync({ session: optimisticSession });
        }

        await visitItem(project);
        toast.style = Toast.Style.Success;
        toast.title = session ? "Session saved" : "Session started";

        if (!props.returnToRoot) {
          pop();
        }
      } catch (submitError) {
        const shown = toast;

        if (shown) {
          shown.style = Toast.Style.Failure;
          shown.title = `Couldn't save the session: ${String(submitError)}`;
        } else {
          await showToast({
            style: Toast.Style.Failure,
            title: `Couldn't save the session: ${String(submitError)}`,
          });
        }
      }
    },
  });

  if (session && session.lockdown !== false) {
    return (
      <List>
        <List.EmptyView icon={Icon.Lock} title="Session is locked" />
      </List>
    );
  }

  return (
    <Form
      navigationTitle={props.navigationTitle}
      isLoading={isFetchingNeighbors}
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title={props.kind === "start" ? "Start Session" : "Save Session"}
            icon={Icon.Checkmark}
            onSubmit={handleSubmit}
          />
        </ActionPanel>
      }
    >
      <Form.TextField
        title="Description"
        placeholder="What are you working on?"
        {...itemProps.title}
      />
      <Form.Dropdown
        title="Project"
        placeholder="Select a project"
        isLoading={isFetching}
        {...itemProps.project_id}
      >
        {projects.map((project) => (
          <Form.Dropdown.Item
            key={project.id}
            value={project.id}
            title={project.name}
          />
        ))}
      </Form.Dropdown>
      <Form.Checkbox label="Remote Work" {...itemProps.is_remote} />
      <Form.Separator />
      <Form.DatePicker
        title="Start Time"
        type={Form.DatePicker.Type.DateTime}
        min={
          neighbors?.previous?.end_datetime
            ? new Date(neighbors.previous.end_datetime)
            : undefined
        }
        max={
          values.end_datetime ??
          (neighbors?.next
            ? new Date(neighbors.next.start_datetime)
            : undefined)
        }
        {...itemProps.start_datetime}
      />
      {props.kind === "edit" ? (
        <Form.DatePicker
          title="End Time"
          type={Form.DatePicker.Type.DateTime}
          min={values.start_datetime ?? undefined}
          max={
            neighbors?.next
              ? new Date(neighbors.next.start_datetime)
              : undefined
          }
          {...itemProps.end_datetime}
        />
      ) : null}
      {error ? <Form.Description text={error.message} /> : null}
      {neighborsError ? (
        <Form.Description text={neighborsError.message} />
      ) : null}
    </Form>
  );
}

export const PushedSessionForm = withQueryClient(SessionForm);

export default SessionForm;
