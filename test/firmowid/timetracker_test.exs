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

  describe "hours_records" do
    alias Firmowid.Timetracker.HoursRecord

    import Firmowid.TimetrackerFixtures

    @invalid_attrs %{month: nil, year: nil, number_of_hours: nil}

    test "list_hours_records/0 returns all hours_records" do
      hours_record = hours_record_fixture()
      assert Timetracker.list_hours_records() == [hours_record]
    end

    test "get_hours_record!/1 returns the hours_record with given id" do
      hours_record = hours_record_fixture()
      assert Timetracker.get_hours_record!(hours_record.id) == hours_record
    end

    test "create_hours_record/1 with valid data creates a hours_record" do
      valid_attrs = %{month: 42, year: 42, number_of_hours: 42}

      assert {:ok, %HoursRecord{} = hours_record} = Timetracker.create_hours_record(valid_attrs)
      assert hours_record.month == 42
      assert hours_record.year == 42
      assert hours_record.number_of_hours == 42
    end

    test "create_hours_record/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Timetracker.create_hours_record(@invalid_attrs)
    end

    test "update_hours_record/2 with valid data updates the hours_record" do
      hours_record = hours_record_fixture()
      update_attrs = %{month: 43, year: 43, number_of_hours: 43}

      assert {:ok, %HoursRecord{} = hours_record} = Timetracker.update_hours_record(hours_record, update_attrs)
      assert hours_record.month == 43
      assert hours_record.year == 43
      assert hours_record.number_of_hours == 43
    end

    test "update_hours_record/2 with invalid data returns error changeset" do
      hours_record = hours_record_fixture()
      assert {:error, %Ecto.Changeset{}} = Timetracker.update_hours_record(hours_record, @invalid_attrs)
      assert hours_record == Timetracker.get_hours_record!(hours_record.id)
    end

    test "delete_hours_record/1 deletes the hours_record" do
      hours_record = hours_record_fixture()
      assert {:ok, %HoursRecord{}} = Timetracker.delete_hours_record(hours_record)
      assert_raise Ecto.NoResultsError, fn -> Timetracker.get_hours_record!(hours_record.id) end
    end

    test "change_hours_record/1 returns a hours_record changeset" do
      hours_record = hours_record_fixture()
      assert %Ecto.Changeset{} = Timetracker.change_hours_record(hours_record)
    end
  end
end
