defmodule FirmowidWeb.UserSessionController do
  use FirmowidWeb, :controller

  alias Firmowid.Accounts
  alias FirmowidWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Konto zostało utworzone pomyślnie!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/ustawienia/bezpieczenstwo")
    |> create(params, "Hasło zostało zaktualizowane pomyślnie!")
  end

  def create(conn, params) do
    create(conn, params, nil)
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn = UserAuth.log_in_user(conn, user, user_params)

      if info do
        LiveToast.put_toast(conn, :info, info)
      else
        conn
      end
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.

      conn
      |> LiveToast.put_toast(:error, "Niewłaściwy email lub hasło.")
      |> redirect(to: ~p"/zaloguj")
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
