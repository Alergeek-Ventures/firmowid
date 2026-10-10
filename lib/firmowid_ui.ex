defmodule FirmowidUI do
  @moduledoc "Entrypoint for UI components shared by the browser and MCP interfaces."

  @doc "Defines an interface-independent function component."
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component
      use Gettext, backend: Firmowid.Gettext

      import Phoenix.HTML

      alias Phoenix.LiveView.JS
    end
  end

  @doc "Imports the shared UI component environment."
  defmacro __using__(:html), do: html()
end
