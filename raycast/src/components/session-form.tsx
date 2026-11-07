import {
  Action,
  ActionPanel,
  Form,
  Icon,
  List,
  showToast,
  Toast,
  useNavigation,
} from "@raycast/api";
import { FormValidation, useForm, useFrecencySorting } from "@raycast/utils";
import { useMutation, useQuery } from "@tanstack/react-query";

import type { Session } from "../lib/api";
import {
  startSessionMutationOptions,
  editSessionMutationOptions,
} from "../lib/mutations";
import { projectsOptions, sessionNeighborsOptions } from "../lib/queries";

type SessionFormProps = {
  navigationTitle?: string;
} & (
  | { kind: "start"; onStart?: () => Promise<void> }
  | { kind: "edit"; session: Session; onSaved?: () => Promise<void> }
);

function SessionForm(props: SessionFormProps) {
  const { pop } = useNavigation();
  const { data, error, isLoading } = useQuery(projectsOptions);

  const start = useMutation(startSessionMutationOptions);

  const edit = useMutation(editSessionMutationOptions);

  const session = props.kind === "edit" ? props.session : undefined;

  const {
    data: neighbors,
    error: neighborsError,
    isLoading: isLoadingNeighbors,
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
      start_datetime: session ? new Date(session.start_datetime) : null,
      end_datetime: session?.end_datetime
        ? new Date(session.end_datetime)
        : null,
    },
    validation: {
      title: FormValidation.Required,
      project_id: FormValidation.Required,
      start_datetime: session ? FormValidation.Required : undefined,
      end_datetime: session?.end_datetime ? FormValidation.Required : undefined,
    },
    async onSubmit(values) {
      let windowClosed = false;
      let toast: Toast | undefined;

      try {
        const input = {
          title: values.title,
          project_id: values.project_id,
          is_remote: values.is_remote,
        };

        const project = projects.find(
          (project) => project.id === values.project_id
        );

        if (!project) {
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
          start_datetime: session
            ? (values.start_datetime?.toISOString() ?? session.start_datetime)
            : new Date().toISOString(),
          end_datetime: values.end_datetime?.toISOString(),
        };

        if (props.kind === "start" && props.onStart) {
          await props.onStart();
          windowClosed = true;
        }

        toast = await showToast({
          style: Toast.Style.Animated,
          title: session ? "Saving session…" : "Starting session…",
        });

        const pendingToast = toast;

        const request = session
          ? edit.mutateAsync({
              session: optimisticSession,
              input: {
                ...input,
                id: session.id,
                start_datetime: values.start_datetime?.toISOString(),
                end_datetime: values.end_datetime?.toISOString(),
              },
            })
          : start.mutateAsync({ session: optimisticSession });

        void (async () => {
          try {
            await request;
            pendingToast.style = Toast.Style.Success;
            pendingToast.title = session ? "Session saved" : "Session started";
          } catch (error) {
            pendingToast.style = Toast.Style.Failure;
            pendingToast.title = `Couldn't ${session ? "save" : "start"} the session: ${String(error)}`;
          }
        })();

        if (props.kind === "edit" && props.onSaved) {
          windowClosed = true;
        }
        await Promise.all([
          visitItem(project),
          props.kind === "edit" && props.onSaved
            ? props.onSaved()
            : windowClosed
              ? Promise.resolve()
              : pop(),
        ]);
      } catch (error) {
        const shown = toast;

        if (shown) {
          shown.style = Toast.Style.Failure;
          shown.title = `Couldn't save the session: ${String(error)}`;
        } else {
          await showToast({
            style: Toast.Style.Failure,
            title: `Couldn't save the session: ${String(error)}`,
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
      isLoading={isLoadingNeighbors}
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
        isLoading={isLoading}
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
      {props.kind === "edit" ? (
        <>
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
        </>
      ) : null}
      {error ? <Form.Description text={error.message} /> : null}
      {neighborsError ? (
        <Form.Description text={neighborsError.message} />
      ) : null}
    </Form>
  );
}

export default SessionForm;
