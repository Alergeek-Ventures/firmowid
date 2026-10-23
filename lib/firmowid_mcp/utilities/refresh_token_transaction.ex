defmodule FirmowidMcp.Utilities.RefreshTokenTransaction do
  @moduledoc "Serializes HTTP refresh rotation and chain revocation with account credential changes."

  @behaviour Plug

  alias AshAuthentication.Phoenix.Oauth2Server.Errors
  alias AshAuthentication.Phoenix.Oauth2Server.ProtocolRouter
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
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
      # The native router sends from inside the transaction. Its response is
      # captured by the first before_send callback, before the adapter or any
      # other callback runs, so tokens and revocation results leave only after the
      # commit and a slow client cannot hold the locks.
      ref = make_ref()
      defer = fn conn -> throw({ref, conn}) end

      fn ->
        # The stored opaque-token hash fixes the user; request user IDs are never
        # consulted and no selected fields escape. This is only a lock, not an
        # authentication read: blocked or concurrently deleted users must still
        # receive the native protocol response rather than a lookup exception.
        User
        |> Ash.Query.filter(id == ^token.user_id)
        |> Ash.Query.select([:id])
        |> Ash.Query.lock(:for_update)
        # credo:disable-for-next-line AshCredo.Check.Warning.AuthorizeFalse
        |> Ash.read_one!(action: :read, authorize?: false)

        # The library commits rotation, successor insertion and chain revocation
        # separately. Hold the same user-first lock as password/archive through
        # all of them, and commit reuse revocation even for an invalid_grant response.
        # Native reuse revokes before checking client binding, so known tokens
        # must serialize even when a different client is presented.
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

        # A successor that cannot be issued (the account was blocked after the
        # rotation) rolls the rotation back with it before the native router
        # answers, so answer as it does when the issuance fails.
        {:error, %Ash.Changeset{action: %{name: :issue}}} ->
          {status, code, description} = Errors.describe_token_error(:server_error)
          Errors.send_oauth_error(conn, status, code, description)
      end
    else
      _ -> ProtocolRouter.call(conn, opts)
    end
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
