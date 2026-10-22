defmodule FirmowidMcp.Session do
  @moduledoc "Short-lived, app-bound LiveView capabilities issued after MCP OAuth authorization."

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope

  @salt "mcp-app-session-v1"
  @lifetime 900

  @doc "Binds a mount to the authenticated user, tenant, app and original OAuth expiry."
  @spec issue(Plug.Conn.t(), String.t(), map()) :: String.t()
  def issue(conn, resource_uri, query) do
    actor = Ash.PlugHelpers.get_actor(conn)
    tenant = Ash.PlugHelpers.get_tenant(conn)
    claims = conn.assigns.oauth_claims
    Scope.new!(actor, tenant)

    Phoenix.Token.sign(FirmowidMcp.endpoint(), @salt, %{
      actor_id: actor.id,
      tenant: tenant,
      resource_uri: resource_uri,
      query: query,
      confirmation_id: Ash.UUIDv7.generate(),
      expires_at: min(claims["exp"], System.system_time(:second) + @lifetime)
    })
  end

  # An authentication read, so blocked accounts (see User `:access_block`) are not found.
  @authentication_context %{private: %{ash_authentication?: true}}

  @doc "Revalidates expiry, account access and organization membership on mount and every interaction."
  @spec authorize(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def authorize(token, resource_uri) when is_binary(token) do
    with {:ok,
          %{
            resource_uri: ^resource_uri,
            actor_id: id,
            tenant: tenant,
            confirmation_id: confirmation_id
          } = claims} <-
           Phoenix.Token.verify(FirmowidMcp.endpoint(), @salt, token, max_age: @lifetime),
         true <- claims.expires_at > System.system_time(:second),
         {:ok, %User{} = user} <- Core.get_user(id, context: @authentication_context),
         {:ok, scope} <- Scope.new(Core.load_member(user), tenant) do
      {:ok,
       %{
         scope: scope,
         query: claims.query,
         confirmation_id: confirmation_id,
         expires_at: claims.expires_at
       }}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authorize(_, _), do: {:error, :unauthorized}

  @doc """
  Allows the application and ChatGPT sandbox HTTPS origins for the cookie-free socket.

  Development disables the endpoint's origin check (config/dev.exs), so the
  `/development/mcp` host also works on http://localhost:PORT.
  """
  @spec allowed_origin?(URI.t()) :: boolean()
  def allowed_origin?(%URI{} = uri) do
    own = URI.parse(FirmowidMcp.endpoint().url())

    FirmowidMcp.endpoint().config(:check_origin) == false or
      {uri.scheme, uri.host, uri.port} == {own.scheme, own.host, own.port} or
      (uri.scheme == "https" and uri.port == 443 and is_binary(uri.host) and
         (uri.host == "web-sandbox.oaiusercontent.com" or
            String.ends_with?(uri.host, ".web-sandbox.oaiusercontent.com")))
  end
end
