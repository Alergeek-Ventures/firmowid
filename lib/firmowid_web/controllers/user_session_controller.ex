defmodule FirmowidWeb.UserSessionController do
  use FirmowidWeb, :controller

  alias Firmowid.Accounts
  alias FirmowidWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Zalogowano.")
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> UserAuth.log_in_user(user, user_params)

      LiveToast.send_toast(:info, info)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> redirect(to: ~p"/users/log_in")

      LiveToast.send_toast(:error, "Niewłaściwy email lub hasło")
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/users/log_in")

    LiveToast.send_toast(:info, "Wylogowano.")
  end
end
