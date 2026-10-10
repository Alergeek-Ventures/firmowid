defmodule FirmowidWeb.Mcp.Apps do
  @moduledoc "Explicit registry of feature-owned MCP Apps exposed by this endpoint."

  @doc "Returns the configured presentation modules."
  @spec all() :: [module()]
  def all, do: Application.fetch_env!(:firmowid, :mcp_apps)

  @doc "Finds the presentation for an exposed tool without deriving modules from input."
  @spec for_tool(String.t()) :: module() | nil
  def for_tool(name), do: Enum.find(all(), &(&1.tool_name() == name))

  @doc "Finds the presentation registered for a resource URI."
  @spec for_resource(String.t()) :: module() | nil
  def for_resource(uri), do: Enum.find(all(), &(&1.resource_uri() == uri))
end
