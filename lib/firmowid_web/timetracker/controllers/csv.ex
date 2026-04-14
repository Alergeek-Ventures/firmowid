defmodule FirmowidWeb.Timetracker.Controllers.Csv do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session
  alias FirmowidWeb.Infrastructure.Controllers.FileDownload
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  action_fallback FirmowidWeb.Infrastructure.Controllers.Fallback

  def salaries(conn, %{"month" => month_str, "year" => year_str}) do
    case conn.assigns.current_user.role do
      :admin ->
        scope = conn.assigns.ash_scope
        month = String.to_integer(month_str)
        year = String.to_integer(year_str)
        csv_content = build_salaries_csv(month, year, scope)

        send_download(conn, {:binary, csv_content},
          filename: "wyplaty_#{month}_#{year}.csv",
          content_type: "text/csv",
          disposition: :attachment
        )

      _ ->
        {:error, :unauthorized}
    end
  end

  def salaries(conn, _params) do
    conn
    |> put_flash(:error, "Podaj miesiąc i rok dla eksportu CSV.")
    |> redirect(to: ~p"/zarzadzanie/pracownicy")
  end

  def project(conn, %{"id" => project_id, "month" => month_str, "year" => year_str}) do
    scope = conn.assigns.ash_scope
    month = String.to_integer(month_str)
    year = String.to_integer(year_str)

    with :admin <- conn.assigns.current_user.role,
         {:ok, project} when not is_nil(project) <-
           AshProject.get(project_id, scope: scope, not_found_error?: false) do
      csv_content = build_project_tasks_csv(project_id, month, year, scope)
      project_name = FileDownload.clean_filename(project.name)

      send_download(conn, {:binary, csv_content},
        filename: "#{project_name}_#{month}_#{year}.csv",
        content_type: "text/csv",
        disposition: :attachment
      )
    else
      _ -> {:error, :unauthorized}
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp build_salaries_csv(month, year, scope) do
    as_of_date = Date.new!(year, month, 1)

    hours_records = Timetracker.list_hours_records!(%{month: month, year: year}, scope: scope)
    hr_by_user = Map.new(hours_records, &{&1.user_id, &1})

    users =
      [scope: scope]
      |> Core.list_users!()
      |> Enum.filter(fn user ->
        case Map.get(hr_by_user, user.id) do
          nil -> false
          %{number_of_hours: hours} -> Decimal.eq?(hours, Decimal.new(0)) == false
        end
      end)

    salaries = AshUserSalary.as_of!(as_of_date, scope: scope)
    salary_by_user = Map.new(salaries, &{&1.user_id, &1.hourly_rate})

    users
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn user ->
      hr = hr_by_user[user.id]
      rate = salary_by_user[user.id]

      %{
        name: user.name,
        hourly_rate: rate,
        number_of_hours: hr.number_of_hours,
        salary: salary_amount(rate, hr.number_of_hours)
      }
    end)
    |> CSV.encode(
      headers: [
        name: "Imie i Nazwisko",
        hourly_rate: "Stawka godzinowa",
        number_of_hours: "Liczba godzin",
        salary: "Wynagrodzenie"
      ]
    )
    |> Enum.join()
  end

  defp build_project_tasks_csv(project_id, month, year, scope) do
    Session
    |> Ash.Query.for_read(:list, %{project_id: project_id, month: month, year: year}, scope: scope)
    |> Ash.Query.load(:duration)
    |> Ash.Query.load(:user)
    |> Ash.Query.sort(start_datetime: :asc)
    |> Ash.read!(scope: scope)
    |> Enum.map(fn session ->
      %{
        user: session.user && (session.user.name || session.user.email),
        date: session.start_datetime |> DateTime.to_date() |> Date.to_iso8601(),
        duration: TimeFormatter.format_duration(session.duration || 0),
        title: session.title
      }
    end)
    |> CSV.encode(headers: [user: "Użytkownik", date: "Data", duration: "Czas trwania", title: "Tytuł"])
    |> Enum.join()
  end

  defp salary_amount(nil, _hours), do: Decimal.new(0)

  defp salary_amount(rate, hours) do
    Decimal.mult(rate, Decimal.new(hours))
  end
end
