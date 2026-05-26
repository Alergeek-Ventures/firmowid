defmodule FirmowidWeb.Infrastructure.Hooks.FeatureFlags do
  @moduledoc """
  LiveView on-mount hook that evaluates PostHog feature flags once per mount.

  The resolved booleans are assigned under `:feature_flags` so layouts and
  components can branch without triggering additional network calls during
  render.
  """

  import Phoenix.Component

  alias FirmowidWeb.Infrastructure.Flags
  alias Phoenix.LiveView.Socket

  @doc """
  Assigns resolved feature flags for the current user.
  """
  @spec on_mount(:default, map(), map(), Socket.t()) ::
          {:cont, Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    feature_flags = Flags.evaluate_for_user(socket.assigns[:current_user])

    {:cont, assign(socket, :feature_flags, feature_flags)}
  end
end
