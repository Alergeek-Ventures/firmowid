defmodule FirmowidMcp.Widgets do
  @moduledoc "Feature-owned widgets exposed by the MCP endpoint."

  @widgets [
    FirmowidMcp.Ksef.Connection,
    FirmowidMcp.Invoicing.IssueInvoice,
    FirmowidMcp.Invoicing.IssueCorrection
  ]

  @doc "Returns the widget modules exposed by this interface."
  @spec all() :: [module()]
  def all, do: @widgets

  @doc "Finds the presentation for an exposed tool without deriving modules from input."
  @spec for_tool(String.t()) :: module() | nil
  def for_tool(name), do: Enum.find(all(), &(&1.tool_name() == name))

  @doc "Finds the presentation registered for a resource URI."
  @spec for_resource(String.t()) :: module() | nil
  def for_resource(uri), do: Enum.find(all(), &(&1.resource_uri() == uri))

  @doc "Runs the authorized AshAi data tool used by a widget, without invoking its presentation tool."
  @spec execute(module(), map(), Firmowid.Ash.Scope.t()) ::
          {:ok, map(), term()} | {:error, term()}
  def execute(app, arguments, %{actor: actor, tenant: tenant}) do
    tool =
      [
        otp_app: :firmowid,
        tools: [String.to_existing_atom(app.data_tool_name())],
        actor: actor,
        tenant: tenant
      ]
      |> AshAi.exposed_tools()
      |> Enum.find(&(to_string(&1.name) == app.data_tool_name()))

    case tool do
      nil ->
        {:error, :forbidden}

      tool ->
        AshAi.Tools.execute(tool, arguments, %{actor: actor, tenant: tenant}, encode?: false)
    end
  end
end
