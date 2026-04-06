defmodule FirmowidWeb.Auth.Controllers.SessionApi do
  @moduledoc """
  API authentication controller for token-based login.

  Uses Ash Authentication to verify credentials and generate JWT tokens.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Core.User

  action_fallback FirmowidWeb.Infrastructure.Controllers.Fallback

  def create(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- authenticate_user(email, password),
         {:ok, token, _claims} <- AshAuthentication.Jwt.token_for_user(user) do
      json(conn, %{token: token})
    end
  end

  defp authenticate_user(email, password) do
    # Get the password strategy and attempt sign-in
    strategy = AshAuthentication.Info.strategy!(User, :password)

    case AshAuthentication.Strategy.action(strategy, :sign_in, %{
           "username" => email,
           "password" => password
         }) do
      {:ok, user} -> {:ok, user}
      :ok -> {:error, :unauthorized}
      {:error, _reason} -> {:error, :unauthorized}
    end
  end
end
