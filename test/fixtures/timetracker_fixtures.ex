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

  def unique_project_name, do: "project_#{System.unique_integer()}"

  def project_fixture(attrs \\ %{}) do
    params = %{name: attrs[:name] || unique_project_name()}
    tenant = attrs[:organization_id] || raise "organization_id is required for project_fixture"

    {:ok, project} = AshProject.create(params, tenant: tenant, authorize?: false, actor: %{})
    project
  end

  def session_fixture(attrs \\ %{}) do
    tenant = attrs[:organization_id] || raise "organization_id is required for session_fixture"
    project_id = attrs[:project_id] || project_fixture(%{organization_id: tenant}).id

    params = %{
      title: attrs[:title] || "Test Session",
      project_id: project_id,
      user_id: attrs[:user_id],
      start_datetime: attrs[:start_datetime] || DateTime.utc_now(),
      is_remote: attrs[:is_remote] || false
    }

    opts = [tenant: tenant, authorize?: false, actor: %{}]

    {:ok, session} = AshSession.create(params, opts)

    if attrs[:end_datetime] do
      {:ok, session} = AshSession.update(session, %{end_datetime: attrs[:end_datetime]}, opts)
      session
    else
      session
    end
  end

  def user_project_fixture(user_id, project_id, organization_id \\ nil) do
    alias Firmowid.Ash.Timetracker.ProjectUser, as: AshProjectUser

    # organization_id can be passed explicitly; if not, it must be set via test context
    tenant = organization_id || raise "organization_id is required for user_project_fixture"

    {:ok, pu} =
      AshProjectUser.create(
        %{user_id: user_id, project_id: project_id},
        tenant: tenant,
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

    tenant = attrs[:organization_id] || raise "organization_id is required for user_salary_fixture"

    {:ok, salary} =
      AshUserSalary.create_with_retire(params, tenant: tenant, authorize?: false, actor: %{})

    salary
  end
end
