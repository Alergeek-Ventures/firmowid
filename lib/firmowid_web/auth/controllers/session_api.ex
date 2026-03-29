defmodule FirmowidWeb.Auth.Controllers.SessionApi do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Accounts

  action_fallback FirmowidWeb.Infrastructure.Controllers.Fallback

  def create(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- get_user(email, password) do
      token = Accounts.generate_user_session_token(user)

      json(conn, %{token: Base.url_encode64(token)})
    end
  end

  defp get_user(email, password) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end
end
