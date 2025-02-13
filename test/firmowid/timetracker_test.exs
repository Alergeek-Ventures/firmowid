defmodule Firmowid.TimetrackerTest do
  use Firmowid.DataCase
  import Firmowid.AccountsFixtures
  alias Firmowid.Timetracker

  test "works" do
    user = user_fixture()

    Repo.put_org_id(user.organization_id)

    project_list = Timetracker.list_projects_with_users()

    assert project_list == []
  end

  test "lists projects with users" do
    user = user_fixture()

    Repo.put_org_id(user.organization_id)

    {:ok, _} =
      Timetracker.create_project(%{name: "test project", organization_id: user.organization_id})

    project_list = Timetracker.list_projects_with_users()

    [project] = project_list

    assert project.name == "test project"
    assert project.users == []

    {:ok, _} = Timetracker.add_user_to_project(user.id, project.id)

    user =
      user
      |> Repo.preload(:projects)

    [users_project] = user.projects

    assert users_project.id == project.id
    assert users_project.name == "test project"

    project_list_updated = Timetracker.list_projects_with_users()

    [project_updated] = project_list_updated

    assert project_updated.name == "test project"
    assert length(project_updated.users) == 1
  end
end
