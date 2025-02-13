defmodule FirmowidWeb.HoursRecordController do
  use FirmowidWeb, :controller

  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Blobs
  @dialyzer {:no_return, pdf: 2}

  def pdf(conn, %{"date" => date}) do
    evaluate = %{
      expression: """
      document.querySelector('body').classList.add('bg-white');
      """
    }

    url_with_protocol = FirmowidWeb.Endpoint.url()
    domain = FirmowidWeb.Endpoint.host()

    {:ok, result} =
      ChromicPDF.print_to_pdf(
        {:url, "#{url_with_protocol}/czasosledz/ewidencja/#{date}/pdf-preview"},
        set_cookie: %{
          name: "_firmowid_key",
          value: conn.cookies["_firmowid_key"],
          domain: domain
        },
        output: fn path ->
          conn
          |> put_resp_header(
            "content-disposition",
            "attachment; filename=Ewidencja #{date}.pdf"
          )
          |> send_file(200, path)
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
      Timetracker.get_sessions_duration_in_month(conn.assigns.current_user.id, date)
      |> div(3600)
      |> round()

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
        |> Map.get(:avatar_url)
    )
  end

  def download(conn, %{"id" => id}) do
    Bodyguard.permit!(Timetracker, :read_hours_records, conn.assigns.current_user)

    record = Timetracker.get_hours_record!(id)
    url = Blobs.get_blob_url(record.blob_id, conn.assigns.current_org.id)

    {:ok, file} = Req.get(url)

    conn
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"Ewidencja_#{record.year}_#{record.month}_#{record.user.name}.pdf\""
    )
    |> send_resp(200, file.body)
  end
end
