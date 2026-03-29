defmodule FirmowidWeb.Infrastructure.Hooks.CurrentPath do
  @moduledoc """
  LiveView hook for saving the current request URI.

  This hook attaches a handle_params hook that saves the current URI
  to the socket assigns as :current_uri for use in templates and LiveViews.

  ## Usage

  Add to your LiveView's live_session:

      live_session :my_session,
        on_mount: [
          {FirmowidWeb.Infrastructure.Hooks.CurrentPath, :save_request_uri}
        ] do
        # your routes
      end
  """

  def on_mount(:save_request_uri, _params, _session, socket) do
    socket = Phoenix.LiveView.attach_hook(socket, :save_request_path, :handle_params, &save_request_path/3)

    {:cont, socket}
  end

  defp save_request_path(_params, url, socket) do
    socket = Phoenix.Component.assign(socket, :current_uri, URI.parse(url))

    {:cont, socket}
  end
end
