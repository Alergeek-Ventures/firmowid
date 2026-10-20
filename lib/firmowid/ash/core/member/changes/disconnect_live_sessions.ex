defmodule Firmowid.Ash.Core.Member.Changes.DisconnectLiveSessions do
  @moduledoc """
  Disconnects the member's open LiveViews after a change to their authority.

  LiveViews keep the actor loaded at mount. Disconnecting them makes the browser
  reconnect and mount again with the current role, without signing the user out.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Ash.Core.Token
  alias Firmowid.Ash.Core.User

  require Ash.Query

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  def change(changeset, _opts, context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, member} ->
        disconnect(member, context)
        {:ok, member}

      _changeset, error ->
        error
    end)
  end

  @doc false
  @impl true
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) :: {:ok, Ash.Changeset.t()}
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp disconnect(member, context) do
    subject = AshAuthentication.user_to_subject(%User{id: member.user_id})
    opts = Ash.Context.to_opts(context, context: %{private: %{ash_authentication?: true}})

    Token
    |> Ash.Query.filter(subject == ^subject and purpose == "user" and expires_at > now())
    |> Ash.Query.select([:jti])
    |> Ash.read!(opts)
    |> Enum.each(&FirmowidWeb.Core.Endpoint.broadcast("users_sessions:#{&1.jti}", "disconnect", %{}))
  end
end
