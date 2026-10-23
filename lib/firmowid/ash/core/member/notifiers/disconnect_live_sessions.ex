defmodule Firmowid.Ash.Core.Member.Notifiers.DisconnectLiveSessions do
  @moduledoc """
  Disconnects the member's open LiveViews after the authority transaction commits.

  LiveViews keep the actor loaded at mount. Disconnecting them makes the browser
  reconnect and mount again with the current role, without signing the user out.
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

  @doc "Invalidates cached actors only after Ash delivers the committed membership notification."
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
