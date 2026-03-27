defmodule Firmowid.Management do
  @moduledoc false

  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Repo
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.UserSalary

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
      left_join: us in subquery(Timetracker.user_salaries_as_of_query(date)),
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

    case Timetracker.create_user_salary(%{user_id: employee.user.id, hourly_rate: new_hourly_wage}) do
      {:ok, %UserSalary{}} -> :ok
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
    |> Repo.preload([:projects, sessions: sessions_query])
    |> case do
      nil ->
        nil

      user ->
        hourly_rate =
          case Timetracker.get_user_salary_as_of(user.id, date) do
            nil -> Decimal.new(0)
            %{hourly_rate: rate} -> rate
          end

        user
        |> Repo.preload(projects: [sessions: fn _ids -> user.sessions end])
        |> Map.put(:hourly_rate, hourly_rate)
        |> Map.put(:hours_record, Timetracker.get_hours_record_by_month(user.id, date))
        |> Map.put(:time_worked, user.sessions |> Enum.map(& &1.duration) |> Enum.sum())
    end
  end
end
