defmodule FirmowidWeb.HoursRecord.Controllers.Record do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers

  @dialyzer {:no_return, pdf: 2}

  # sobelow_skip ["Traversal.SendFile"]
  # This is safe because pdf_path is not user-controlled
  def pdf(conn, %{"date" => date}) do
    scope = conn.assigns.ash_scope

    # Get avatar URL and convert to data URI
    avatar_url =
      conn.assigns.current_org
      |> Ash.load!([avatar_blob: [:url]], scope: scope)
      |> Map.get(:avatar_blob)
      |> case do
        %{url: url} -> url
        _ -> nil
      end

    avatar_data_uri = PdfHelpers.url_to_data_uri(avatar_url)

    date_parsed = Date.from_iso8601!(date)
    start_date = Date.beginning_of_month(date_parsed)
    end_date = Date.end_of_month(date_parsed)

    session_query =
      Ash.Query.for_read(
        AshSession,
        :list,
        %{
          month: date_parsed.month,
          year: date_parsed.year,
          user_id: conn.assigns.current_user.id
        },
        scope: scope
      )

    %{total: duration_seconds} =
      Ash.aggregate!(session_query, {:total, :sum, field: :duration, default: 0}, scope: scope)

    total_hours = Timetracker.seconds_to_hours(duration_seconds)

    # Render HTML to string
    html_content =
      PdfHelpers.render_pdf_html(
        FirmowidWeb.HoursRecord.Components.PdfTemplate,
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
    scope = conn.assigns.ash_scope

    date = Date.from_iso8601!(date)
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)

    session_query =
      Ash.Query.for_read(
        AshSession,
        :list,
        %{month: date.month, year: date.year, user_id: conn.assigns.current_user.id},
        scope: scope
      )

    %{total: duration_seconds} =
      Ash.aggregate!(session_query, {:total, :sum, field: :duration, default: 0}, scope: scope)

    total_hours = Timetracker.seconds_to_hours(duration_seconds)

    render(conn, :preview,
      layout: false,
      name: conn.assigns.current_user.name,
      employment_date: conn.assigns.current_user.employment_date,
      start_date: start_date,
      end_date: end_date,
      hours: total_hours,
      avatar_url:
        conn.assigns.current_org
        |> Ash.load!([avatar_blob: [:url]], scope: scope)
        |> Map.get(:avatar_blob)
        |> case do
          %{url: url} -> url
          _ -> nil
        end,
      avatar_data_uri: nil
    )
  end

  # sobelow_skip ["XSS.SendResp"]
  # This is safe because this gets downloaded not executed by browser
  def download(conn, %{"id" => id}) do
    scope = conn.assigns.ash_scope

    case AshHoursRecord.get(id, scope: scope, load: [:user, blob: [:url]], not_found_error?: false) do
      {:ok, nil} ->
        conn
        |> LiveToast.put_toast(:error, "Nie masz dostępu do tej ewidencji godzin.")
        |> redirect(to: ~p"/czasosledz")

      {:ok, record} ->
        url = record.blob.url
        {:ok, file} = Req.get(url)

        conn
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"Ewidencja_#{record.year}_#{record.month}_#{record.user.name}.pdf\""
        )
        |> send_resp(200, file.body)

      {:error, _error} ->
        conn
        |> LiveToast.put_toast(:error, "Nie masz dostępu do tej ewidencji godzin.")
        |> redirect(to: ~p"/czasosledz")
    end
  end
end
