defmodule FirmowidWeb.CsvController do
  use FirmowidWeb, :controller

  alias Ash.Error.Forbidden
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session, as: AshSession

  def salaries(conn, %{"month" => month_str, "year" => year_str}) do
    scope = conn.assigns.ash_scope
    month = String.to_integer(month_str)
    year = String.to_integer(year_str)

    case AshUserSalary.salaries_csv(month, year, scope: scope) do
      {:ok, csv_content} ->
        send_download(conn, {:binary, csv_content},
          filename: "wyplaty_#{month}_#{year}.csv",
          content_type: "text/csv",
          disposition: :attachment
        )

    send_download(conn, {:binary, csv_content},
      filename: "wyplaty_#{month}_#{year}.csv",
      content_type: "text/csv",
      disposition: :attachment
    )
  end

  def project(conn, %{"id" => project_id, "month" => month_str, "year" => year_str}) do
    scope = conn.assigns.ash_scope
    month = String.to_integer(month_str)
    year = String.to_integer(year_str)

    case AshProject.get(project_id, scope: scope, not_found_error?: false) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, project} ->
        case AshSession.project_tasks_csv(project_id, month, year, scope: scope) do
          {:ok, csv_content} ->
            project_name = FirmowidWeb.FileController.clean_filename(project.name)

            send_download(conn, {:binary, csv_content},
              filename: "#{project_name}_#{month}_#{year}.csv",
              content_type: "text/csv",
              disposition: :attachment
            )

          {:error, %Forbidden{}} ->
            {:error, :unauthorized}
        end
    end
  end
end
