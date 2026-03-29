defmodule FirmowidWeb.Core.Toast do
  @moduledoc """
  Toast styling and CSS class generation.
  """

  @doc """
  Generates CSS classes for flash/toast messages based on the assigns.
  """
  def toast_class_fn(assigns) do
    [
      # base classes
      "group/toast z-100 pointer-events-auto relative w-full items-center justify-between origin-center overflow-hidden rounded-lg p-4 shadow-lg border col-start-1 col-end-1 row-start-1 row-end-2",
      # start hidden if javascript is enabled
      "[@media(scripting:enabled)]:opacity-0 [@media(scripting:enabled){[data-phx-main]_&}]:opacity-100",
      # used to hide the disconnected flashes
      if(assigns[:rest][:hidden] == true, do: "hidden", else: "flex"),
      # override styles per severity
      assigns[:kind] == :success && "bg-greenBg text-greenText",
      assigns[:kind] == :notice && "bg-blueBg text-blueText",
      assigns[:kind] == :info && "bg-lightGreyBg text-black",
      assigns[:kind] == :error && "!text-redText !bg-redBg"
    ]
  end
end
