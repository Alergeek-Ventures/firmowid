# credo:disable-for-this-file ExDNA.Credo
# Cross-file duplicate is framework/controller wiring boilerplate shared across
# features; extracting it would require a broader controller abstraction, not a
# couple-line refactor.
defmodule FirmowidWeb.Timetracker.Controllers.Csv do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Core
  alias Firmowid.Invoicing.Services.MonthDownloadEntries
  alias Firmowid.Payroll
  alias Firmowid.TimeFormatter
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams

  action_fallback FirmowidWeb.Infrastructure.Controllers.Fallback

  def salaries(conn, %{"miesiac" => month_str, "rok" => year_str}) do
    case conn.assigns.current_user.member.role do
      :admin ->
        case parse_export_period(%{"miesiac" => month_str, "rok" => year_str}) do
          {:ok, month, year} ->
            scope = conn.assigns.ash_scope
            csv_content = build_salaries_csv(month, year, scope)

            send_download(conn, {:binary, csv_content},
              filename: "wyplaty_#{month}_#{year}.csv",
              content_type: "text/csv",
              disposition: :attachment
            )

          :error ->
            conn
            |> put_flash(:error, gettext("Enter a valid month and year for the CSV export."))
            |> redirect(to: ~p"/zarzadzanie/pracownicy")
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  def salaries(conn, _params) do
    conn
    |> put_flash(:error, gettext("Enter the month and year for the CSV export."))
    |> redirect(to: ~p"/zarzadzanie/pracownicy")
  end

  def project(conn, %{"id" => project_id, "miesiac" => month_str, "rok" => year_str}) do
    scope = conn.assigns.ash_scope

    with :admin <- conn.assigns.current_user.member.role,
         {:ok, month, year} <- parse_export_period(%{"miesiac" => month_str, "rok" => year_str}),
         {:ok, project} when not is_nil(project) <-
           Project.get(project_id, scope: scope, not_found_error?: false) do
      csv_content = build_project_tasks_csv(project_id, month, year, scope)
      project_name = MonthDownloadEntries.clean_filename(project.name)

      send_download(conn, {:binary, csv_content},
        filename: "#{project_name}_#{month}_#{year}.csv",
        content_type: "text/csv",
        disposition: :attachment
      )
    else
      :error ->
        conn
        |> put_flash(:error, gettext("Enter a valid month and year for the CSV export."))
        |> redirect(to: ~p"/zarzadzanie/projekty/#{project_id}")

      _ ->
        {:error, :unauthorized}
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp build_salaries_csv(month, year, scope) do
    hours_records =
      Timetracker.list_hours_records!(%{month: month, year: year}, load: [:member], scope: scope)

    hr_by_user = Map.new(hours_records, &{&1.member.user_id, &1})

    users =
      [load: [:member], scope: scope]
      |> Core.list_users!()
      |> Enum.filter(fn user ->
        case Map.get(hr_by_user, user.id) do
          nil -> false
          %{number_of_hours: hours} -> Decimal.eq?(hours, Decimal.new(0)) == false
        end
      end)

    date = Date.end_of_month(Date.new!(year, month, 1))

    salaries =
      Payroll.list_salaries!(%{active_at: date}, scope: scope, load: [:member])

    salary_by_user = Map.new(salaries, &{&1.member.user_id, &1.hourly_rate})

    users
    |> Enum.sort_by(& &1.member.name)
    |> Enum.map(fn user ->
      hr = hr_by_user[user.id]
      rate = salary_by_user[user.id]

      %{
        name: user.member.name,
        hourly_rate: rate,
        number_of_hours: hr.number_of_hours,
        salary: salary_amount(rate, hr.number_of_hours)
      }
    end)
    |> CSV.encode(
      escape_formulas: true,
      headers: [
        name: pgettext("payroll CSV header", "Full name"),
        hourly_rate: gettext("Hourly rate"),
        number_of_hours: gettext("Number of hours"),
        salary: gettext("Remuneration")
      ]
    )
    |> Enum.join()
  end

  defp build_project_tasks_csv(project_id, month, year, scope) do
    %{project_id: project_id, month: month, year: year}
    |> Timetracker.query_to_list_sessions(scope: scope)
    |> Ash.Query.load(:duration)
    |> Ash.Query.load(member: :user)
    |> Ash.Query.sort(start_datetime: :asc)
    |> Ash.read!(scope: scope)
    |> Enum.map(fn session ->
      %{
        user: session.member.name || session.member.user.email,
        date: session.start_datetime |> DateTime.to_date() |> Date.to_iso8601(),
        duration: TimeFormatter.format_duration(session.duration || 0),
        title: session.title
      }
    end)
    |> CSV.encode(
      escape_formulas: true,
      headers: [
        user: gettext("User"),
        date: gettext("Date"),
        duration: gettext("Duration"),
        title: gettext("Title")
      ]
    )
    |> Enum.join()
  end

  defp salary_amount(nil, _hours), do: Decimal.new(0)

  defp salary_amount(rate, hours) do
    Decimal.mult(rate, Decimal.new(hours))
  end

  defp parse_export_period(params) do
    month = QueryParams.parse_integer(params, "miesiac", nil)
    year = QueryParams.parse_integer(params, "rok", nil)

    case {month, year} do
      {month, year} when is_integer(month) and is_integer(year) ->
        case Date.new(year, month, 1) do
          {:ok, _date} -> {:ok, month, year}
          {:error, _reason} -> :error
        end

      _other ->
        :error
    end
  end
end
