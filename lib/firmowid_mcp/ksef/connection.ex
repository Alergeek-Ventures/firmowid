defmodule FirmowidMcp.Ksef.Connection do
  @moduledoc "MCP presentation of the organization's KSeF connection workflow."

  @doc "Returns the tool that opens KSeF connection settings."
  @spec tool_name() :: String.t()
  def tool_name, do: "show_ksef_connection"

  @doc "Returns the read-only connection status tool."
  @spec data_tool_name() :: String.t()
  def data_tool_name, do: "get_ksef_connection_status"

  @doc "Returns the stable AshAi resource identifier; the transport adds a content hash."
  @spec resource_uri() :: String.t()
  def resource_uri, do: "ui://firmowid/ksef/connection.html"

  @doc "Describes the widget to ChatGPT so it need not repeat the interface in chat."
  @spec widget_description() :: String.t()
  def widget_description do
    "Interactive KSeF connection setup inside ChatGPT. Shows connection status and lets an " <>
      "authorized administrator connect using a trusted profile or certificate directly in this widget. " <>
      "The widget provides all setup instructions. After it opens successfully, do not add a status " <>
      "table, summary, explanation or follow-up beneath it. Wait for the user to act. An initial " <>
      "disconnected status is expected before setup, not a failed connection attempt."
  end

  @doc "Returns the connection LiveView."
  @spec live_view() :: module()
  def live_view, do: FirmowidMcp.Ksef.Views.Connection

  @doc "Describes opening the widget and reading status; connection changes require UI interaction."
  @spec annotations() :: map()
  def annotations, do: %{"readOnlyHint" => true, "destructiveHint" => false, "openWorldHint" => false}
end
