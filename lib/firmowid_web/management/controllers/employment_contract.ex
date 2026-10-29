defmodule FirmowidWeb.Management.Controllers.EmploymentContract do
  @moduledoc "Controller for downloading employment contract PDFs."
  use FirmowidWeb, :controller

  alias Firmowid.Payroll

  # sobelow_skip ["XSS.SendResp"]
  # Filename is sanitized before being placed in the header. The response body
  # is the binary file content from S3, not user-controlled HTML/JS.
  def download(conn, %{"id" => id}) do
    scope = conn.assigns.ash_scope
    current_user = conn.assigns.current_user

    case Payroll.get_employment_contract(id,
           scope: scope,
           load: [:member, blob: [:url]]
         ) do
      {:ok, nil} ->
        conn
        |> LiveToast.put_toast(:error, gettext("You do not have access to this file."))
        |> redirect(to: documents_return_path(current_user))

      {:ok, record} ->
        url = record.blob.url

        case Req.get(url) do
          {:ok, %{status: 200, body: body}} ->
            safe_filename =
              sanitize_filename("Umowa_#{record.member.name || "pracownik"}_#{record.starts_at}.pdf")

            conn
            |> put_resp_header(
              "content-disposition",
              "attachment; filename=\"#{safe_filename}\""
            )
            |> send_resp(200, body)

          {:ok, %{status: status}} ->
            conn
            |> LiveToast.put_toast(
              :error,
              gettext("Could not download the file (status: %{status}).", status: status)
            )
            |> redirect(to: documents_return_path(current_user, record.member.user_id))

          {:error, _reason} ->
            conn
            |> LiveToast.put_toast(:error, gettext("Could not download the file."))
            |> redirect(to: documents_return_path(current_user, record.member.user_id))
        end

      {:error, _error} ->
        conn
        |> LiveToast.put_toast(:error, gettext("You do not have access to this file."))
        |> redirect(to: documents_return_path(current_user))
    end
  end

  defp documents_return_path(%{member: %{role: :admin}}) do
    ~p"/zarzadzanie/pracownicy"
  end

  defp documents_return_path(_user) do
    ~p"/ustawienia/profil"
  end

  defp documents_return_path(%{member: %{role: :admin}}, user_id) when is_binary(user_id) do
    ~p"/zarzadzanie/pracownicy/#{user_id}/dokumenty"
  end

  defp documents_return_path(%{member: %{role: :admin}}, _user_id) do
    ~p"/zarzadzanie/pracownicy"
  end

  defp documents_return_path(_user, _user_id) do
    ~p"/ustawienia/profil"
  end

  defp sanitize_filename(filename) do
    filename
    |> String.replace(~r/[\x00-\x1f\x7f\/\\<>|:"?*]/, "_")
    |> String.replace(~r/\.+/, ".")
    |> String.trim()
  end
end
