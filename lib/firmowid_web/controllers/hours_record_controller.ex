defmodule FirmowidWeb.HoursRecordController do
  use FirmowidWeb, :controller

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
    date = Date.from_iso8601!(date)
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)

    # Replace with actual hours calculation
    total_hours = 160

    render(conn, :preview,
      layout: false,
      name: "John Doe",
      # Replace with actual employment date
      employment_date: ~D[2023-01-01],
      start_date: start_date,
      end_date: end_date,
      hours: total_hours
    )
  end
end
