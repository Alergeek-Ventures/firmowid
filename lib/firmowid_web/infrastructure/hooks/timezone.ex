defmodule FirmowidWeb.Infrastructure.Hooks.Timezone do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    timezone =
      if connected?(socket) do
        get_connect_params(socket)["timezone"]
      end ||
        "Europe/Warsaw"

    {:cont, assign(socket, timezone: timezone)}
  end
end
