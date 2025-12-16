defmodule FirmowidWeb.CsvController do
  use FirmowidWeb, :controller

  alias Firmowid.Timetracker

  def salaries(conn, %{"month" => month_str, "year" => year_str}) do
    Bodyguard.permit!(Timetracker, :read_hours_records, conn.assigns.current_user, nil)
    month = String.to_integer(month_str)
    year = String.to_integer(year_str)

    csv_content = Timetracker.get_salaries_csv(month, year)

    send_download(conn, {:binary, csv_content},
      filename: "wyplaty_#{month}_#{year}.csv",
      content_type: "text/csv",
      disposition: :attachment
    )
  end

  def project(conn, %{"id" => project_id, "month" => month_str, "year" => year_str}) do
    Bodyguard.permit!(Timetracker, :read_projects, conn.assigns.current_user, nil)
    month = String.to_integer(month_str)
    year = String.to_integer(year_str)

    project = Timetracker.get_project(project_id)

    if project do
      csv_content = Timetracker.get_project_tasks_csv(project_id, month, year)

      project_name = FirmowidWeb.FileController.clean_filename(project.name)

      send_download(conn, {:binary, csv_content},
        filename: "#{project_name}_#{month}_#{year}.csv",
        content_type: "text/csv",
        disposition: :attachment
      )
    else
      put_status(conn, :not_found)
    end
  end
end
