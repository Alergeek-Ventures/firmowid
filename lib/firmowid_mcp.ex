defmodule FirmowidMcp do
  @moduledoc "MCP interface composition and shared embedded LiveView environment."

  # AshAi UI resources belong to a domain but do not require any Ash.Resource.
  # credo:disable-for-next-line AshCredo.Check.Warning.EmptyDomain
  use Ash.Domain, extensions: [AshAi]

  alias FirmowidMcp.Invoicing
  alias FirmowidMcp.Ksef.Connection

  mcp_resources do
    mcp_ui_resource :ksef_connection, Connection.resource_uri(),
      html: {FirmowidMcp.Runtime, :document, []},
      title: "KSeF connection",
      description: "Connect the organization's KSeF account using the existing administrator workflow.",
      domain: nil,
      prefers_border: true
  end

  @doc "Composes the model instructions owned by the exposed MCP features."
  @spec instructions() :: String.t()
  def instructions, do: Enum.join([Invoicing.instructions(), Connection.instructions()], "\n")

  @doc "Returns the Phoenix endpoint hosting this interface."
  @spec endpoint() :: module()
  def endpoint, do: :firmowid |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(:endpoint)

  @doc "Defines a cookie-free embedded LiveView using shared UI helpers."
  @spec live_view() :: Macro.t()
  def live_view do
    quote do
      use Phoenix.LiveView, layout: false, log: false
      use Gettext, backend: Firmowid.Gettext

      import FirmowidUI.Components.Inputs
      import Phoenix.HTML

      alias Phoenix.LiveView.JS
    end
  end

  @doc "Imports the MCP presentation environment."
  defmacro __using__(:live_view), do: live_view()
end
