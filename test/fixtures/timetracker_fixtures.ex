defmodule Firmowid.TimetrackerFixtures do
  @moduledoc """
  Test helpers for creating Timetracker entities.

  Uses Ash code interface with `authorize?: false` to bypass policies
  while still exercising the resource's action logic (validations,
  changes, multitenancy).
  """

  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias Firmowid.Repo

  def unique_project_name, do: "project_#{System.unique_integer()}"

  def project_fixture(attrs \\ %{}) do
    params = %{name: attrs[:name] || unique_project_name()}
    tenant = attrs[:organization_id] || Repo.get_org_id()

    {:ok, project} = AshProject.create(params, tenant: tenant, authorize?: false, actor: %{})
    project
  end

  def session_fixture(attrs \\ %{}) do
    params = %{
      title: attrs[:title] || "Test Session",
      project_id: attrs[:project_id] || project_fixture().id,
      user_id: attrs[:user_id],
      start_datetime: attrs[:start_datetime] || DateTime.utc_now(),
      is_remote: attrs[:is_remote] || false
    }

    tenant = attrs[:organization_id] || Repo.get_org_id()
    opts = [tenant: tenant, authorize?: false, actor: %{}]

    {:ok, session} = AshSession.create(params, opts)

    if attrs[:end_datetime] do
      {:ok, session} = AshSession.update(session, %{end_datetime: attrs[:end_datetime]}, opts)
      session
    else
      session
    end
  end

  def user_project_fixture(user_id, project_id) do
    alias Firmowid.Ash.Timetracker.ProjectUser, as: AshProjectUser

    {:ok, pu} =
      AshProjectUser.create(
        %{user_id: user_id, project_id: project_id},
        tenant: Repo.get_org_id(),
        authorize?: false,
        actor: %{}
      )

    pu
  end

  def user_salary_fixture(attrs \\ %{}) do
    params = %{
      hourly_rate: attrs[:hourly_rate] || Decimal.new("50.00"),
      user_id: attrs[:user_id] || raise("user_id is required for user_salary_fixture")
    }

    tenant = attrs[:organization_id] || Repo.get_org_id()

    {:ok, salary} =
      AshUserSalary.create_with_retire(params, tenant: tenant, authorize?: false, actor: %{})

    salary
  end
end
