defmodule Firmowid.Employee do
  @moduledoc false

  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Repo
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.UserSalary

  def authorize(:read_employee, %{role: :admin}, _), do: true
  def authorize(:read_employee_projects, %{role: :admin}, _), do: true
  def authorize(:edit_employee_projects, %{role: :admin}, _), do: true
  def authorize(:read_employee_profile, %{role: :admin}, _), do: true
  def authorize(:read_employee_documents, %{role: :admin}, _), do: true
  def authorize(:read_employee_leaves, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  def list_employee_details(user_id, filter_date) do
    salary_query = from(us in UserSalary, where: is_nil(us.deleted_at), limit: 1)

    sessions_query =
      from(s in Session,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^filter_date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^filter_date.year),
        group_by: [s.user_id, s.title, s.project_id],
        select: %{
          title: s.title,
          project_id: s.project_id,
          time_worked:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }
      )

    result =
      Accounts.User
      |> Repo.get!(user_id)
      |> Repo.preload(user_salaries: salary_query)
      |> Repo.preload(:projects)
      |> Repo.preload(sessions: sessions_query)

    result
    |> Map.put(:hourly_rate, List.first(result.user_salaries).hourly_rate || 0)
    |> Map.put(:time_worked, Enum.sum(Enum.map(result.sessions, & &1.time_worked)))
    |> Map.put(
      :projects,
      Enum.map(result.projects, fn project ->
        sessions = Enum.filter(result.sessions, &(&1.project_id == project.id))
        Map.put(project, :sessions, sessions)
      end)
    )
  end
end
