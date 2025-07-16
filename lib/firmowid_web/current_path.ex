defmodule FirmowidWeb.CurrentPath do
  def on_mount(:save_request_uri, _params, _session, socket) do
    socket =
      socket
      |> Phoenix.LiveView.attach_hook(
        :save_request_path,
        :handle_params,
        &save_request_path/3
      )

    {:cont, socket}
  end

  defp save_request_path(_params, url, socket) do
    socket =
      socket
      |> Phoenix.Component.assign(
        :current_uri,
        URI.parse(url)
      )

    {:cont, socket}
  end
end
