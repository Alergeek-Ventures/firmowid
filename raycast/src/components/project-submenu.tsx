import { Icon, MenuBarExtra, showToast, Toast } from "@raycast/api";
import { useFrecencySorting } from "@raycast/utils";
import { useMutation, useQuery } from "@tanstack/react-query";

import type { Project, Session } from "../lib/api";
import { editSessionMutationOptions } from "../lib/mutations";
import { projectsOptions } from "../lib/queries";

export default function ProjectSubmenu({ session }: { session: Session }) {
  const { data, error, isFetching } = useQuery({
    ...projectsOptions,
    refetchOnMount: false,
    retryOnMount: false,
  });

  const { data: projects, visitItem } = useFrecencySorting(data, {
    namespace: "projects",
  });

  const mutation = useMutation(editSessionMutationOptions);

  async function changeProject(project: Project) {
    if (project.id === session.project.id) {
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Changing project…",
    });

    try {
      await Promise.all([
        mutation.mutateAsync({
          session: { ...session, project },
          input: { id: session.id, project_id: project.id },
        }),
        visitItem(project),
      ]);
      toast.style = Toast.Style.Success;
      toast.title = "Project changed";
    } catch (mutationError) {
      toast.style = Toast.Style.Failure;
      toast.title = `Couldn't change the project: ${String(mutationError)}`;
    }
  }

  return (
    <MenuBarExtra.Submenu title="Change Project…" icon={Icon.Folder}>
      {isFetching ? (
        <MenuBarExtra.Item title="Loading projects…" />
      ) : error ? (
        <MenuBarExtra.Item
          title="Couldn't load projects"
          tooltip={error.message}
        />
      ) : null}
      {projects.map((project) => (
        <MenuBarExtra.Item
          key={project.id}
          title={project.name}
          icon={
            project.id === session.project.id ? Icon.Checkmark : Icon.Folder
          }
          onAction={() => changeProject(project)}
        />
      ))}
      {!isFetching && !error && projects.length === 0 ? (
        <MenuBarExtra.Item title="No projects" />
      ) : null}
    </MenuBarExtra.Submenu>
  );
}
