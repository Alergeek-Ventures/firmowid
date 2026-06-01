defmodule FirmowidWeb.Management.Controllers.EmploymentContract do
  @moduledoc "Controller for downloading employment contract PDFs."
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Payroll

  # sobelow_skip ["XSS.SendResp"]
  # Filename is sanitized before being placed in the header. The response body
  # is the binary file content from S3, not user-controlled HTML/JS.
  def download(conn, %{"id" => id}) do
    scope = conn.assigns.ash_scope

    case Payroll.get_employment_contract(id,
           scope: scope,
           load: [blob: [:url]]
         ) do
      {:ok, nil} ->
        conn
        |> LiveToast.put_toast(:error, "Nie masz dostępu do tego pliku.")
        |> redirect(to: ~p"/zarzadzanie/pracownicy")

      {:ok, record} ->
        url = record.blob.url

        case Req.get(url) do
          {:ok, %{status: 200, body: body}} ->
            safe_filename =
              sanitize_filename("Umowa_#{record.worker_full_name}_#{record.starts_at}.pdf")

            conn
            |> put_resp_header(
              "content-disposition",
              "attachment; filename=\"#{safe_filename}\""
            )
            |> send_resp(200, body)

          {:ok, %{status: status}} ->
            conn
            |> LiveToast.put_toast(:error, "Nie udało się pobrać pliku (status: #{status}).")
            |> redirect(to: ~p"/zarzadzanie/pracownicy/#{record.user_id}/dokumenty")

          {:error, _reason} ->
            conn
            |> LiveToast.put_toast(:error, "Nie udało się pobrać pliku.")
            |> redirect(to: ~p"/zarzadzanie/pracownicy/#{record.user_id}/dokumenty")
        end

      {:error, _error} ->
        conn
        |> LiveToast.put_toast(:error, "Nie masz dostępu do tego pliku.")
        |> redirect(to: ~p"/zarzadzanie/pracownicy")
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> String.replace(~r/[\x00-\x1f\x7f\/\\<>|:"?*]/, "_")
    |> String.replace(~r/\.+/, ".")
    |> String.trim()
  end
end
