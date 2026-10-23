defmodule Firmowid.Ash.Core.Member.Notifiers.DisconnectLiveSessions do
  @moduledoc """
  Disconnects LiveViews after membership changes commit, so reconnecting reloads
  the actor's permissions while preserving browser sessions.
  """

  use Ash.Notifier

  alias Ash.Notifier.Notification
  alias Firmowid.Ash.Core.Token
  alias Firmowid.Ash.Core.User

  require Ash.Query

  @authentication_context %{private: %{ash_authentication?: true}}

  @doc false
  @impl true
  @spec load(Ash.Resource.t(), Ash.Resource.Actions.action()) :: [atom()]
  def load(_resource, _action), do: [:user_id]

  @doc "Disconnects active browser sessions affected by a committed membership change."
  @impl true
  @spec notify(Notification.t()) :: :ok
  def notify(%Notification{action: %{name: action}, data: member})
      when action in [:update_role, :archive, :unarchive, :destroy] do
    subject = AshAuthentication.user_to_subject(%User{id: member.user_id})

    Token
    |> Ash.Query.filter(subject == ^subject and purpose == "user" and expires_at > now())
    |> Ash.Query.select([:jti])
    |> Ash.read!(context: @authentication_context)
    |> Enum.each(&FirmowidWeb.Core.Endpoint.broadcast("users_sessions:#{&1.jti}", "disconnect", %{}))
  end

  def notify(_notification), do: :ok
end
