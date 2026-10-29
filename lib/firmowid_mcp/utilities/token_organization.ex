defmodule FirmowidMcp.Utilities.TokenOrganization do
  @moduledoc """
  Sets the Ash tenant of an OAuth token request to the organization of its grant.

  The OAuth server mints the conn's tenant into the access token's `tenant` claim
  and scopes the grant lookup and the new refresh token to it, so an access token
  and a rotated refresh token keep the organization chosen on the consent screen.
  Install in `:oauth_api` before protocol routing; only `/oauth/token` is
  inspected. A grant without an organization, or one that is not found, leaves the
  tenant unset, and the OAuth server then rejects or exchanges it as before. The
  parameters are read like the OAuth server reads them, from the query and the
  body; the grant's exchange also rejects a request outside its organization
  (`Firmowid.Core.Changes.RequireGrantTenant`).
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [set_tenant: 2]

  alias Firmowid.Core

  @auth_context %{private: %{ash_authentication?: true}}

  @doc "Accepts the pipeline's keyword options without changing them."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Sets the tenant of token requests only."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with ["oauth", "token"] <- Enum.map(conn.path_info, &URI.decode/1),
         organization_id when is_binary(organization_id) <- organization_id(conn.params) do
      set_tenant(conn, organization_id)
    else
      _ -> conn
    end
  end

  defp organization_id(%{"grant_type" => "authorization_code", "code" => id}) when is_binary(id) do
    case Core.get_oauth_authorization_code(id, context: @auth_context) do
      {:ok, code} -> code.organization_id
      {:error, _} -> nil
    end
  end

  defp organization_id(%{"grant_type" => "refresh_token", "refresh_token" => raw}) when is_binary(raw) do
    # The OAuth server stores refresh tokens by this hash (`AshAuthentication.Oauth2Server.Token`).
    hash = :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower)

    case Core.get_oauth_refresh_token_by_hash(hash, context: @auth_context) do
      {:ok, refresh_token} -> refresh_token.organization_id
      {:error, _} -> nil
    end
  end

  defp organization_id(_params), do: nil
end
