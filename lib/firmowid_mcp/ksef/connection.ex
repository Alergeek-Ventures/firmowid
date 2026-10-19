defmodule FirmowidMcp.Ksef.Connection do
  @moduledoc "MCP presentation of the organization's KSeF connection workflow."

  @doc "Returns the KSeF setup instructions advertised by the MCP server."
  @spec instructions() :: String.t()
  def instructions do
    """
    Recheck the status after the user completes connection. Never ask for KSeF tokens, passwords,
    private keys or signed authentication files in chat; these belong only in the connection widget.
    After show_ksef_connection successfully opens its widget, stop and let the user interact with it.
    Do not repeat its status, setup instructions or a summary in chat beneath the widget.
    The administrator completes setup directly in the embedded widget, not in a separate Firmowid page.
    Opening the widget does not attempt a connection: an initial disconnected status is expected,
    not evidence of a failed attempt. Explain actual tool errors only when the widget cannot be opened.
    """
  end

  @doc "Returns the tool that opens KSeF connection settings."
  @spec tool_name() :: String.t()
  def tool_name, do: "show_ksef_connection"

  @doc "Returns the read-only connection status tool."
  @spec data_tool_name() :: String.t()
  def data_tool_name, do: "get_ksef_connection_status"

  @doc "Returns the stable AshAi resource identifier; the transport adds a content hash."
  @spec resource_uri() :: String.t()
  def resource_uri, do: "ui://firmowid/ksef/connection.html"

  @doc "Describes the widget to the host model so it need not repeat the interface in chat."
  @spec widget_description() :: String.t()
  def widget_description do
    "Interactive KSeF connection setup inside the chat. Shows connection status and lets an " <>
      "authorized administrator connect using a trusted profile or certificate directly in this widget. " <>
      "The widget provides all setup instructions. After it opens successfully, do not add a status " <>
      "table, summary, explanation or follow-up beneath it. Wait for the user to act. An initial " <>
      "disconnected status is expected before setup, not a failed connection attempt."
  end

  @doc "Returns the connection LiveView."
  @spec live_view() :: module()
  def live_view, do: FirmowidMcp.Ksef.Views.Connection
end
