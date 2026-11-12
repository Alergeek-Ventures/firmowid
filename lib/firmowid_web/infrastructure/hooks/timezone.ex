defmodule FirmowidWeb.Infrastructure.Hooks.Timezone do
  @moduledoc """
  Assigns `:timezone`: the browser's time zone once the socket is connected, or
  Warsaw when the browser reports none the time zone database knows (ICU reports
  `Etc/Unknown` when it cannot determine the system's zone).
  """
  import Phoenix.Component
  import Phoenix.LiveView

  @default_timezone "Europe/Warsaw"

  def on_mount(:default, _params, _session, socket) do
    timezone = connected?(socket) && get_connect_params(socket)["timezone"]

    {:cont, assign(socket, timezone: if(known?(timezone), do: timezone, else: @default_timezone))}
  end

  defp known?(timezone) when is_binary(timezone), do: match?({:ok, _now}, DateTime.now(timezone))
  defp known?(_timezone), do: false
end
