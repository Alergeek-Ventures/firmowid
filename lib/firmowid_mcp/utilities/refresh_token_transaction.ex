defmodule FirmowidMcp.Utilities.RefreshTokenTransaction do
  @moduledoc "Serializes HTTP OAuth exchange and token registration with account credential changes."

  @behaviour Plug

  alias AshAuthentication.Phoenix.Oauth2Server.Errors
  alias AshAuthentication.Phoenix.Oauth2Server.ProtocolRouter
  alias Firmowid.Core
  alias Firmowid.Core.OauthAuthorizationCode
  alias Firmowid.Core.User
  alias Firmowid.Repo
  alias FirmowidMcp.Utilities.AccessToken

  require Ash.Query

  @auth_context %{private: %{ash_authentication?: true}}

  @doc false
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: ProtocolRouter.init(opts)

  @doc """
  Keeps native protocol processing and its revocation effects in one user-locked
  transaction, and sends the native response only after it commits.
  """
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case grant(conn) do
      {:ok, token} when not is_nil(token) -> transact(conn, opts, token.user_id)
      _ -> ProtocolRouter.call(conn, opts)
    end
  end

  defp transact(conn, opts, user_id) do
    ref = make_ref()
    defer = fn conn -> throw({ref, conn}) end

    # Exchange, JWT registration and reuse revocation must share the user lock
    # held by password changes and membership archival, including error responses.
    fn ->
      user = lock_user(user_id)

      # ProtocolRouter sends immediately and has no transaction hook. Capture its
      # response before other callbacks or the adapter run, then send after commit.
      response =
        try do
          conn |> Plug.Conn.register_before_send(defer) |> ProtocolRouter.call(opts)
        catch
          {^ref, response} -> response
        end

      if response.status == 200 and Enum.map(conn.path_info, &URI.decode/1) == ["token"] do
        %{"access_token" => token} = Jason.decode!(response.resp_body)
        AccessToken.store!(token, user)
      end

      response
    end
    |> Repo.transaction()
    |> case do
      {:ok, response} ->
        response.private[:before_send]
        |> update_in(&List.delete(&1, defer))
        |> Plug.Conn.send_resp()
        |> Plug.Conn.halt()

      # Ash rolls back the outer transaction if successor issuance fails.
      {:error, %Ash.Changeset{action: %{name: :issue}}} ->
        {status, code, description} = Errors.describe_token_error(:server_error)
        Errors.send_oauth_error(conn, status, code, description)
    end
  end

  defp lock_user(user_id) do
    # Lock by the stored token's owner, even if blocked or concurrently deleted.
    # Authentication filtering here would bypass the native protocol response.
    User
    |> Ash.Query.filter(id == ^user_id)
    |> Ash.Query.select([:id])
    |> Ash.Query.lock(:for_update)
    # credo:disable-for-next-line AshCredo.Check.Warning.AuthorizeFalse
    |> Ash.read_one!(action: :read, authorize?: false)
  end

  defp grant(%{method: "POST", path_info: path, params: params} = conn) do
    ash_opts = [context: @auth_context, tenant: Ash.PlugHelpers.get_tenant(conn)]

    case Enum.map(path, &URI.decode/1) do
      ["token"] ->
        case params["grant_type"] do
          "authorization_code" -> authorization_code(params["code"], ash_opts)
          "refresh_token" -> refresh_token(params["refresh_token"], ash_opts)
          _ -> :no_grant
        end

      ["revoke"] ->
        refresh_token(params["token"], ash_opts)

      _ ->
        :no_grant
    end
  end

  defp grant(_conn), do: :no_grant

  defp authorization_code(code, opts) when is_binary(code) and code != "", do: Ash.get(OauthAuthorizationCode, code, opts)

  defp authorization_code(_, _), do: :no_grant

  defp refresh_token(raw, opts) when is_binary(raw) and raw != "" do
    hash = :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower)
    Core.get_oauth_refresh_token_by_hash(hash, opts)
  end

  defp refresh_token(_, _), do: :no_grant
end
