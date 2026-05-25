defmodule Firmowid.TimetrackerFixtures do
  @moduledoc """
  Test helpers for creating Timetracker entities.

  Uses Ash code interface with a real admin actor in the target organization,
  so tests exercise resource policies and action logic together.
  """

  alias Firmowid.AccountsFixtures
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.ProjectUser, as: AshProjectUser
  alias Firmowid.Ash.Timetracker.Session, as: AshSession

  require Ash.Query

  def unique_project_name, do: "project_#{System.unique_integer()}"

  def project_fixture(attrs \\ %{}) do
    params = %{name: attrs[:name] || unique_project_name()}
    tenant = attrs[:organization_id] || raise "organization_id is required for project_fixture"
    opts = admin_opts(tenant)

    {:ok, project} = AshProject.create(params, opts)
    project
  end

  def session_fixture(attrs \\ %{}) do
    tenant = attrs[:organization_id] || raise "organization_id is required for session_fixture"
    project_id = attrs[:project_id] || project_fixture(%{organization_id: tenant}).id
    opts = admin_opts(tenant)

    if user_id = attrs[:user_id] do
      ensure_project_user!(user_id, project_id, opts)
    end

    params = %{
      title: attrs[:title] || "Test Session",
      project_id: project_id,
      user_id: attrs[:user_id],
      start_datetime: attrs[:start_datetime] || DateTime.utc_now(),
      is_remote: attrs[:is_remote] || false
    }

    {:ok, session} = AshSession.create(params, opts)

    if attrs[:end_datetime] do
      {:ok, session} = AshSession.update(session, %{end_datetime: attrs[:end_datetime]}, opts)
      session
    else
      session
    end
  end

  def user_project_fixture(user_id, project_id, organization_id \\ nil) do
    # organization_id can be passed explicitly; if not, it must be set via test context
    tenant = organization_id || raise "organization_id is required for user_project_fixture"
    opts = admin_opts(tenant)

    {:ok, pu} = AshProjectUser.create(%{user_id: user_id, project_id: project_id}, opts)

    pu
  end

  def user_salary_fixture(attrs \\ %{}) do
    params = %{
      hourly_rate: attrs[:hourly_rate] || Decimal.new("50.00"),
      user_id: attrs[:user_id] || raise("user_id is required for user_salary_fixture")
    }

    tenant =
      attrs[:organization_id] || raise "organization_id is required for user_salary_fixture"

    opts = admin_opts(tenant)

    {:ok, salary} = Payroll.create_salary(params, opts)

    salary
  end

  defp admin_opts(tenant) do
    [tenant: tenant, actor: AccountsFixtures.admin_fixture(%{organization_id: tenant})]
  end

  defp ensure_project_user!(user_id, project_id, opts) do
    exists? =
      AshProjectUser
      |> Ash.Query.filter(user_id: user_id, project_id: project_id)
      |> Ash.exists?(opts)

    if !exists? do
      {:ok, _project_user} =
        AshProjectUser.create(%{user_id: user_id, project_id: project_id}, opts)
    end

    :ok
  end
end
