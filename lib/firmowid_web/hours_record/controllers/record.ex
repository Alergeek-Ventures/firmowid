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
    {avatar_url, assigns} =
      conn |> record_assigns(Date.from_iso8601!(date)) |> Keyword.pop!(:avatar_url)

    html_content =
      PdfHelpers.render_pdf_html(
        FirmowidWeb.HoursRecord.Components.PdfTemplate,
        :hours_record,
        [layout: false, avatar_data_uri: PdfHelpers.url_to_data_uri(avatar_url)] ++ assigns
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
    render(conn, :preview, [layout: false] ++ record_assigns(conn, Date.from_iso8601!(date)))
  end

  # The acting member's month as the hours record template shows it.
  defp record_assigns(conn, date) do
    %{ash_scope: scope, current_user: user, current_org: org} = conn.assigns
    {:ok, contract} = Payroll.load_current_contract(user.member.id, scope: scope)
    %{avatar_blob: avatar_blob} = Ash.load!(org, [avatar_blob: [:url]], scope: scope)

    [
      name: user.member.name,
      contract_date: contract && (contract.signed_at || contract.starts_at),
      start_date: Date.beginning_of_month(date),
      end_date: Date.end_of_month(date),
      hours: Timetracker.seconds_to_hours(Session.month_duration!(date, scope: scope)),
      avatar_url: avatar_blob && avatar_blob.url
    ]
  end

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
