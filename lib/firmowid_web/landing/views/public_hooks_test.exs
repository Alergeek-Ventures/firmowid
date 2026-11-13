defmodule FirmowidWeb.Landing.Views.PublicHooksTest do
  @moduledoc """
  Public pages load landing.js, which registers only the hooks they render. A hook
  added to a public page but not to landing.js would silently do nothing there.
  """

  use FirmowidWeb.ConnCase, async: true

  @landing_js "assets/js/landing.js"
  @public_paths [
    "/",
    "/cennik",
    "/funkcje",
    "/faq",
    "/open-source",
    "/poradnik",
    "/poradnik/tryb-offline-ksef",
    "/regulamin",
    "/polityka-prywatnosci"
  ]

  test "every hook on a public page is registered in landing.js", %{conn: conn} do
    registered = registered_hooks()

    rendered =
      @public_paths
      |> Enum.flat_map(fn path ->
        html = conn |> get(path) |> html_response(200)
        for [_, hook] <- Regex.scan(~r/phx-hook="([^"]+)"/, html), do: hook
      end)
      |> Enum.uniq()
      # Hooks that ship with LiveView itself.
      |> Enum.reject(&String.starts_with?(&1, "Phoenix."))

    assert rendered != []
    assert rendered -- registered == []
  end

  defp registered_hooks do
    [_, hooks] = Regex.run(~r/startLiveSocket\(\{(.*?)\}\);/s, File.read!(@landing_js))

    for [_, name] <- Regex.scan(~r/^\s*(\w+)[,:]/m, hooks), do: name
  end
end
