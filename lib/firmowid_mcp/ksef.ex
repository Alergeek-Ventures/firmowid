defmodule FirmowidMcp.Ksef do
  @moduledoc """
  Model guidance for the organization's KSeF connection, which is set up only in the
  Firmowid web app: this interface never collects or handles KSeF credentials.
  """

  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  @doc "Returns the web address where an administrator connects KSeF."
  @spec settings_url() :: String.t()
  def settings_url, do: FirmowidMcp.endpoint().url() <> SettingsNavigation.canonical_path(:ksef)

  @doc "Returns the KSeF connection instructions advertised by the MCP server."
  @spec instructions() :: String.t()
  def instructions do
    """
    KSeF is connected only by an organization administrator in the Firmowid web app, at
    #{settings_url()}. This integration has no way to connect KSeF.
    When get_ksef_connection_status reports a disconnected or expired connection, or the confirmation
    widget asks to connect KSeF, give the user that link and explain that issuing invoices needs the connection.
    Do not ask for, accept or discuss KSeF authentication details in the conversation. If the user shares any,
    tell them not to and point them to the link.
    """
  end
end
