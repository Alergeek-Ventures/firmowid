defmodule FirmowidWeb.HoursRecordController do
  use FirmowidWeb, :controller

  alias Firmowid.Accounts
  alias Firmowid.Blobs
  alias Firmowid.Helpers.TimeConverter
  alias Firmowid.Timetracker
  alias FirmowidWeb.PdfHelpers

  @dialyzer {:no_return, pdf: 2}

  # sobelow_skip ["Traversal.SendFile"]
  # This is safe because pdf_path is not user-controlled
  def pdf(conn, %{"date" => date}) do
    # Get avatar URL and convert to data URI
    avatar_url =
      conn.assigns.current_org
      |> Accounts.get_organization_with_avatar()
      |> Map.get(:avatar_url)

    avatar_data_uri = PdfHelpers.url_to_data_uri(avatar_url)

    date_parsed = Date.from_iso8601!(date)
    start_date = Date.beginning_of_month(date_parsed)
    end_date = Date.end_of_month(date_parsed)

    total_hours =
      conn.assigns.current_user.id
      |> Timetracker.get_sessions_duration_in_month(date_parsed)
      |> TimeConverter.time_worked_in_seconds_to_hours()

    # Render HTML to string
    html_content =
      PdfHelpers.render_pdf_html(
        FirmowidWeb.HoursRecord.PdfTemplate,
        :hours_record,
        layout: false,
        name: conn.assigns.current_user.name,
        employment_date: conn.assigns.current_user.employment_date,
        start_date: start_date,
        end_date: end_date,
        hours: total_hours,
        avatar_data_uri: avatar_data_uri
      )

    evaluate = %{
      expression: """
      document.querySelector('body').classList.add('bg-white');
      """
    }

    {:ok, result} =
      ChromicPDF.print_to_pdf(
        {:html, html_content},
        output: fn pdf_path ->
          conn
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=Ewidencja #{date}.pdf"
          )
          |> send_file(200, pdf_path)
        end,
        page_size: "A4",
        evaluate: evaluate,
        print_to_pdf: %{
          marginTop: 0,
          marginLeft: 0,
          marginRight: 0,
          marginBottom: 0,
          scale: 1,
          printBackground: true
        }
      )

    result
  end

  def preview(conn, %{"date" => date}) do
    Bodyguard.permit!(Timetracker, :read_user_hours_records, conn.assigns.current_user)

    date = Date.from_iso8601!(date)
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)

    total_hours =
      conn.assigns.current_user.id
      |> Timetracker.get_sessions_duration_in_month(date)
      |> TimeConverter.time_worked_in_seconds_to_hours()

    render(conn, :preview,
      layout: false,
      name: conn.assigns.current_user.name,
      employment_date: conn.assigns.current_user.employment_date,
      start_date: start_date,
      end_date: end_date,
      hours: total_hours,
      avatar_url:
        conn.assigns.current_org
        |> Accounts.get_organization_with_avatar()
        |> Map.get(:avatar_url),
      avatar_data_uri: nil
    )
  end

  # sobelow_skip ["XSS.SendResp"]
  # This is safe because this gets downloaded not executed by browser
  def download(conn, %{"id" => id}) do
    Bodyguard.permit!(Timetracker, :read_hours_records, conn.assigns.current_user)

    record = Timetracker.get_hours_record!(id)
    url = Blobs.get_blob_url(record.blob_id)

    {:ok, file} = Req.get(url)

    conn
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"Ewidencja_#{record.year}_#{record.month}_#{record.user.name}.pdf\""
    )
    |> send_resp(200, file.body)
  end
end
