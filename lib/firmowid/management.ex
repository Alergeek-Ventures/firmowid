defmodule Firmowid.Management do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Firmowid.Accounts.User
  alias Firmowid.Repo
  alias Firmowid.Timetracker

  defp filter_search(query, ""), do: query

  defp filter_search(query, search) do
    from u in query,
      where: ilike(u.name, ^"%#{search}%") or ilike(u.email, ^"%#{search}%")
  end

  def list_employees(filter_date, archived \\ false, search \\ "") do
    from(u in User,
      # TODO: add database support for archived users
      where: ^archived == false,
      order_by: u.name
    )
    |> filter_search(search)
    |> Repo.all()
    |> Enum.map(fn user ->
      hours = Timetracker.get_sessions_duration_in_month(user.id, filter_date)
      salary = Timetracker.get_latest_user_salary(user.id)

      user
      |> Map.put(:hours, hours)
      |> Map.put(:hourly_rate, salary && salary.hourly_rate)
    end)
  end
end
