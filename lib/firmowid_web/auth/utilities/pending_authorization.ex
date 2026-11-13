defmodule FirmowidWeb.Auth.Utilities.PendingAuthorization do
  @moduledoc """
  An MCP client's authorization request waiting for the account to be ready.

  A person connecting an AI client (such as ChatGPT) may first need to sign up,
  create a company and finish its setup. `FirmowidWeb.Auth.Utilities.ConsentOrganization`
  remembers the client's name in the session, so the registration and setup pages
  can say what they are for, and the authorization request's path, so the setup
  returns to the consent screen once it is done. The consent screen forgets it.

  A request abandoned halfway is forgotten after `@lifetime_seconds`, so a later
  company switch in the same browser session does not lead to an old consent.
  """

  import Plug.Conn, only: [get_session: 2, put_session: 3, delete_session: 2]

  @session_key "mcp_pending_authorization"
  @lifetime_seconds 3600

  @doc "Remembers the client and, once the account is signed in, the request to return to."
  @spec put(Plug.Conn.t(), String.t() | nil, String.t() | nil) :: Plug.Conn.t()
  def put(conn, client_name, return_path) do
    put_session(conn, @session_key, %{
      "client" => client_name,
      "path" => return_path,
      "at" => System.os_time(:second)
    })
  end

  @doc "Forgets the pending authorization."
  @spec delete(Plug.Conn.t()) :: Plug.Conn.t()
  def delete(conn), do: delete_session(conn, @session_key)

  @doc "The name of the client waiting for the account, from a conn or a LiveView session."
  @spec client_name(Plug.Conn.t() | map()) :: String.t() | nil
  def client_name(conn_or_session) do
    case fetch(conn_or_session) do
      %{"client" => client} -> client
      nil -> nil
    end
  end

  @doc "The authorization request to continue with once the setup is done."
  @spec return_path(Plug.Conn.t() | map()) :: String.t() | nil
  def return_path(conn_or_session) do
    case fetch(conn_or_session) do
      %{"path" => path} -> path
      nil -> nil
    end
  end

  defp fetch(%Plug.Conn{} = conn), do: conn |> get_session(@session_key) |> current()
  defp fetch(session) when is_map(session), do: session |> Map.get(@session_key) |> current()

  defp current(%{"at" => at} = pending) do
    if System.os_time(:second) - at < @lifetime_seconds, do: pending
  end

  defp current(nil), do: nil
end
