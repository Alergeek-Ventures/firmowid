defmodule Firmowid.Management do
  @moduledoc false

  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Repo
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.UserSalary

  # employees
  def authorize(:read_employees, %{role: :admin}, _), do: true
  def authorize(:change_user_wages, %{role: :admin}, _), do: true
  def authorize(:create_employee, %{role: :admin}, _), do: true
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

  def list_employees(filter_date, archived \\ false, search \\ "") do
    time_worked_query =
      from(s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^filter_date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^filter_date.year),
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
      left_join: us in UserSalary,
      on: us.user_id == u.id,
      where: is_nil(us.deleted_at),
      left_lateral_join: s in subquery(time_worked_query),
      on: s.user_id == u.id,
      select: %{
        user: u,
        hourly_rate: us.hourly_rate,
        time_worked: coalesce(s.time_worked, 0)
      }
    )
    |> filter_search(search)
    |> Repo.all()
  end

  def update_user_salaries(employees, employees_params) do
    Repo.transaction(fn ->
      Enum.reduce_while(employees, :ok, fn employee, _acc ->
        new_hourly_wage = Decimal.new(employees_params[employee.user.id]["wage"])

        case Timetracker.create_user_salary(%{user_id: employee.user.id, hourly_rate: new_hourly_wage}) do
          {:ok, %UserSalary{}} -> {:cont, :ok}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end
end
