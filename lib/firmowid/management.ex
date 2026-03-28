defmodule Firmowid.Management do
  @moduledoc """
  Admin management context — employee listings, salary details, employee profiles.

  Uses Bodyguard for authorization (not Ash policies). Queries Ash resources
  directly via raw Ecto, bypassing Ash's policy engine and action layer.
  Organization scoping relies on `Repo.prepare_query/3` (process-dict org_id).

  This is intentional during the migration period: Management was written before
  Ash adoption and its queries involve cross-domain joins (User × Session ×
  HoursRecord × UserSalary) that have no Ash equivalent yet. Migrate to Ash
  generic actions with proper policies once cross-domain reads are supported.
  """

  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Ash.Timetracker.Session
  alias Firmowid.Repo

  # employees
  def authorize(:read_employees, %{role: :admin}, _), do: true
  def authorize(:change_user_wages, %{role: :admin}, _), do: true
  def authorize(:create_employee, %{role: :admin}, _), do: true

  def authorize(:read_employee, %{role: :admin}, _), do: true
  def authorize(:read_employee_projects, %{role: :admin}, _), do: true
  def authorize(:edit_employee_projects, %{role: :admin}, _), do: true
  def authorize(:read_employee_profile, %{role: :admin}, _), do: true
  def authorize(:read_employee_documents, %{role: :admin}, _), do: true
  def authorize(:read_employee_leaves, %{role: :admin}, _), do: true

  # projects
  def authorize(:read_projects, %{role: :admin}, _), do: true

  # clients
  def authorize(:read_clients, %{role: :admin}, _), do: true

  # ...
  def authorize(_, _, _), do: false

  defp filter_search(query, ""), do: query

  defp filter_search(query, search) do
    where(query, [user], ilike(user.name, ^"%#{search}%") or ilike(user.email, ^"%#{search}%"))
  end

  def list_employees(date, archived \\ false, search \\ "") do
    time_worked_query =
      from(s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }
      )

    from(u in Accounts.User,
      # TODO: add database support for archived users
      where: ^archived == false,
      left_join: us in subquery(UserSalary.salary_as_of_subquery(date, Repo.get_org_id())),
      on: us.user_id == u.id,
      left_join: s in subquery(time_worked_query),
      on: s.user_id == u.id,
      left_join: hr in HoursRecord,
      on: hr.user_id == u.id and hr.year == ^date.year and hr.month == ^date.month,
      select: %{
        user: u,
        hours_record: hr,
        hourly_rate: us.hourly_rate,
        time_worked: coalesce(s.time_worked, 0)
      }
    )
    |> filter_search(search)
    |> Repo.all()
  end

  def update_user_salaries(employees, employees_params) do
    Repo.transaction(fn ->
      Enum.each(employees, &update_single_salary(&1, employees_params))
    end)
  end

  defp update_single_salary(employee, employees_params) do
    new_hourly_wage = Decimal.new(employees_params[employee.user.id]["wage"])

    # Use Ash create_with_retire which retires existing salary in a change.
    # We skip Ash authorization here because this runs inside a Management
    # Bodyguard-guarded transaction (admin-only), not via an Ash scope.
    case UserSalary
         |> Ash.Changeset.for_create(
           :create_with_retire,
           %{
             user_id: employee.user.id,
             hourly_rate: new_hourly_wage
           },
           actor: %{},
           tenant: Repo.get_org_id()
         )
         |> Ash.create(authorize?: false, actor: %{}) do
      {:ok, _salary} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  def list_employee_details(user_id, date) do
    sessions_query =
      from s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year) and
            s.user_id == ^user_id,
        group_by: [s.user_id, s.project_id, s.title],
        select: %{
          title: s.title,
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }

    Accounts.User
    |> Repo.get(user_id)
    |> Repo.preload(sessions: sessions_query)
    |> case do
      nil ->
        nil

      user ->
        hourly_rate =
          case get_user_salary_as_of(user.id, date) do
            nil -> Decimal.new(0)
            %{hourly_rate: rate} -> rate
          end

        hours_record = get_hours_record_by_month(user.id, date)

        # Group sessions by project and attach to manually loaded projects.
        # We can't use Repo.preload(projects: [sessions: fn ...]) because
        # Ash resources use Ash.NotLoaded (not Ecto.Association.NotLoaded)
        # which confuses Ecto's preload logic.
        sessions_by_project = Enum.group_by(user.sessions, & &1.project_id)

        projects =
          Enum.map(Repo.preload(user, :projects).projects, fn project ->
            Map.put(project, :sessions, Map.get(sessions_by_project, project.id, []))
          end)

        user
        |> Map.put(:projects, projects)
        |> Map.put(:hourly_rate, hourly_rate)
        |> Map.put(:hours_record, hours_record)
        |> Map.put(:time_worked, user.sessions |> Enum.map(& &1.duration) |> Enum.sum())
    end
  end

  # Inlined from old Timetracker — returns the salary active on the given date for a user.
  defp get_user_salary_as_of(user_id, date) do
    import Ecto.Query, only: [where: 3]

    date
    |> UserSalary.salary_as_of_subquery(Repo.get_org_id())
    |> where([us], us.user_id == ^user_id)
    |> Repo.one(skip_organization_id: true)
  end

  # Inlined from old Timetracker.
  defp get_hours_record_by_month(user_id, date) do
    HoursRecord
    |> where([hr], hr.user_id == ^user_id)
    |> where([hr], hr.month == ^date.month and hr.year == ^date.year)
    |> Repo.one()
  end
end
