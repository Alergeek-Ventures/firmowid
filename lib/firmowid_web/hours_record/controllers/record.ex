defmodule FirmowidWeb.HoursRecord.Controllers.Record do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Invoicing.Services.PdfUtils
  alias Firmowid.Payroll
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers

  @dialyzer {:no_return, pdf: 2}

  plug :put_view, html: FirmowidWeb.HoursRecord.Components.RecordHtml

  # sobelow_skip ["XSS.SendResp"]
  # This is safe because pdf_binary is a generated PDF served as a download,
  # not user-controlled HTML executed by the browser.
  def pdf(conn, %{"date" => date}) do
    scope = conn.assigns.ash_scope

    {:ok, contract} =
      Payroll.load_current_contract(conn.assigns.current_user.member.id, scope: scope)

    contract_date = contract && (contract.signed_at || contract.starts_at)

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

    total_hours = Timetracker.seconds_to_hours(Session.month_duration!(date_parsed, scope: scope))

    # Render HTML to string
    html_content =
      PdfHelpers.render_pdf_html(
        FirmowidWeb.HoursRecord.Components.PdfTemplate,
        :hours_record,
        layout: false,
        name: conn.assigns.current_user.member.name,
        contract_date: contract_date,
        start_date: start_date,
        end_date: end_date,
        hours: total_hours,
        avatar_data_uri: avatar_data_uri
      )

    {:ok, pdf_binary} = PdfUtils.render_html_to_pdf(html_content, scale: 1.0)

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=Ewidencja #{date}.pdf"
    )
    |> send_resp(200, pdf_binary)
  end

  def preview(conn, %{"date" => date}) do
    scope = conn.assigns.ash_scope

    {:ok, contract} =
      Payroll.load_current_contract(conn.assigns.current_user.member.id, scope: scope)

    contract_date = contract && (contract.signed_at || contract.starts_at)

    date = Date.from_iso8601!(date)
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)

    total_hours = Timetracker.seconds_to_hours(Session.month_duration!(date, scope: scope))

    render(conn, :preview,
      layout: false,
      name: conn.assigns.current_user.member.name,
      contract_date: contract_date,
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

    case HoursRecord.get(id,
           scope: scope,
           load: [:member, blob: [:url]],
           not_found_error?: false
         ) do
      {:ok, nil} ->
        conn
        |> LiveToast.put_toast(:error, gettext("You do not have access to this timesheet."))
        |> redirect(to: ~p"/czasosledz")

      {:ok, record} ->
        url = record.blob.url
        {:ok, file} = Req.get(url)

        send_download(conn, {:binary, file.body},
          filename: "Ewidencja_#{record.year}_#{record.month}_#{record.member.name}.pdf",
          content_type: "application/octet-stream"
        )

      {:error, _error} ->
        conn
        |> LiveToast.put_toast(:error, gettext("You do not have access to this timesheet."))
        |> redirect(to: ~p"/czasosledz")
    end
  end
end
