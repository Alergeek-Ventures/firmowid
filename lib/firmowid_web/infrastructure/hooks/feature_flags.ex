defmodule FirmowidWeb.Infrastructure.Hooks.FeatureFlags do
  @moduledoc """
  LiveView on-mount hook that synchronizes identity and evaluates PostHog flags.

  The resolved booleans are assigned under `:feature_flags` so layouts and
  components can branch without triggering additional network calls during
  render.
  """

  import Phoenix.Component

  alias Firmowid.Analytics
  alias FirmowidWeb.Infrastructure.Flags
  alias Phoenix.LiveView.Socket

  @doc """
   Synchronizes the current user's person profile and assigns resolved flags.
  """
  @spec on_mount(:default, map(), map(), Socket.t()) ::
          {:cont, Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns[:current_user]
    Analytics.identify_user(user)
    feature_flags = Flags.evaluate_for_user(user)

    {:cont, assign(socket, :feature_flags, feature_flags)}
  end
end
