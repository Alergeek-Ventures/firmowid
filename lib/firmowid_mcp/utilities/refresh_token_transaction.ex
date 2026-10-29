defmodule FirmowidMcp.Utilities.RefreshTokenTransaction do
  @moduledoc "Serializes HTTP refresh rotation and chain revocation with account credential changes."

  @behaviour Plug

  alias AshAuthentication.Phoenix.Oauth2Server.Errors
  alias AshAuthentication.Phoenix.Oauth2Server.ProtocolRouter
  alias Firmowid.Core
  alias Firmowid.Core.User
  alias Firmowid.Repo

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
    ash_opts = [context: @auth_context, tenant: Ash.PlugHelpers.get_tenant(conn)]

    with raw when is_binary(raw) and raw != "" <- refresh_token(conn),
         hash = :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower),
         {:ok, token} <- Core.get_oauth_refresh_token_by_hash(hash, ash_opts) do
      transact(conn, opts, token.user_id)
    else
      _ -> ProtocolRouter.call(conn, opts)
    end
  end

  defp transact(conn, opts, user_id) do
    ref = make_ref()
    defer = fn conn -> throw({ref, conn}) end

    # Rotation, successor issuance and reuse revocation must share the user lock
    # held by password changes and membership archival, including error responses.
    fn ->
      lock_user(user_id)

      # ProtocolRouter sends immediately and has no transaction hook. Capture its
      # response before other callbacks or the adapter run, then send after commit.
      try do
        conn |> Plug.Conn.register_before_send(defer) |> ProtocolRouter.call(opts)
      catch
        {^ref, response} -> response
      end
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

  defp refresh_token(%{method: "POST", path_info: path, params: params}) do
    case Enum.map(path, &URI.decode/1) do
      ["token"] -> if params["grant_type"] == "refresh_token", do: params["refresh_token"]
      ["revoke"] -> params["token"]
      _ -> nil
    end
  end

  defp refresh_token(_conn), do: nil
end
