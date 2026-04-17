defmodule Firmowid.Ash.Timetracker.ProjectTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Timetracker.Project, as: AshProject

  require Ash.Query

  setup :setup_scope

  describe "create/2" do
    test "creates a project", %{scope: scope} do
      {:ok, project} = AshProject.create(%{name: "Test Project"}, scope: scope)

      assert project.name == "Test Project"
      assert is_nil(project.archived_at)
    end
  end

  describe "archive + unarchive" do
    test "archives and unarchives a project", %{scope: scope} do
      project = project_fixture(%{organization_id: scope.tenant})

      {:ok, archived} = AshProject.archive(project, scope: scope)
      assert archived.archived_at

      {:ok, restored} = AshProject.unarchive(archived, scope: scope)
      assert is_nil(restored.archived_at)
    end
  end

  describe "organization owner deletion" do
    test "destroys project-created tag definitions before deleting the account", %{
      user: admin,
      org_id: org_id,
      scope: scope
    } do
      {:ok, project} = AshProject.create(%{name: "Project Cleanup"}, scope: scope)

      assert project.tag_definition_id
      assert :ok = Core.destroy_user(admin, scope: scope)

      refute Core.User
             |> Ash.Query.filter(id == ^admin.id)
             |> Ash.exists?(authorize?: false)

      refute Core.Organization
             |> Ash.Query.filter(id == ^org_id)
             |> Ash.exists?(authorize?: false)

      refute AshProject
             |> Ash.Query.filter(id == ^project.id)
             |> Ash.exists?(actor: admin, authorize?: false, tenant: org_id)

      refute TagDefinition
             |> Ash.Query.filter(id == ^project.tag_definition_id)
             |> Ash.exists?(actor: admin, authorize?: false, tenant: org_id)
    end

    test "rolls back account deletion when the surrounding transaction aborts", %{
      user: admin,
      org_id: org_id,
      scope: scope
    } do
      {:ok, project} = AshProject.create(%{name: "Rollback Project"}, scope: scope)

      assert {:error, %Ash.Error.Unknown.UnknownError{error: "unknown error: :forced_rollback"}} =
               Ash.transact([Core.User, Core.Organization, AshProject, TagDefinition], fn ->
                 assert :ok = Core.destroy_user_in_transaction(admin, scope: scope)

                 Ash.DataLayer.rollback(Core.User, :forced_rollback)
               end)

      assert Core.User
             |> Ash.Query.filter(id == ^admin.id)
             |> Ash.exists?(authorize?: false)

      assert Core.Organization
             |> Ash.Query.filter(id == ^org_id)
             |> Ash.exists?(authorize?: false)

      assert AshProject
             |> Ash.Query.filter(id == ^project.id)
             |> Ash.exists?(actor: admin, authorize?: false, tenant: org_id)

      assert TagDefinition
             |> Ash.Query.filter(id == ^project.tag_definition_id)
             |> Ash.exists?(actor: admin, authorize?: false, tenant: org_id)
    end
  end

  describe "set_users/3" do
    test "assigns users to a project", %{user: user, org_id: org_id, scope: scope} do
      project = project_fixture(%{organization_id: org_id})
      user2 = user_in_org_fixture(org_id)

      {:ok, _} =
        AshProject.set_users([user.id, user2.id], %{project_id: project.id}, scope: scope)

      project_with_users = AshProject.get!(project.id, scope: scope)
      active_ids = project_with_users.users |> Enum.map(& &1.id) |> Enum.sort()

      assert active_ids == Enum.sort([user.id, user2.id])
    end
  end

  defp setup_scope(_) do
    admin = admin_fixture()
    org_id = admin.organization_id

    scope = %Firmowid.Ash.Scope{
      actor: admin,
      tenant: org_id
    }

    %{user: admin, org_id: org_id, scope: scope}
  end
end
