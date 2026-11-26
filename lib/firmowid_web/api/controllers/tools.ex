defmodule FirmowidWeb.Api.Controllers.Tools do
  @moduledoc """
  The public API (`/api/v1`): `POST /api/v1/<tool>` runs an AshAi tool of
  `Firmowid.AiTools.api/0` like an MCP tool call, as the API key's actor in its organization
  (see `FirmowidWeb.Infrastructure.Plugs.ApiKeyAuthentication`), and `GET /api/v1/openapi.json`
  describes the tools. `/api/v1/docs` shows that description.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Api.Utilities.OpenApi
  alias FirmowidWeb.Api.Utilities.Tools

  @doc "Runs the tool with the JSON body as its arguments and returns its result."
  @spec run(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def run(conn, %{"tool" => name}) do
    actor = Ash.PlugHelpers.get_actor(conn)
    tenant = Ash.PlugHelpers.get_tenant(conn)

    case Enum.find(Tools.for_actor(actor, tenant), &(Atom.to_string(&1.name) == name)) do
      nil ->
        if Tools.known?(name),
          do: error(conn, 403, "forbidden", "The key's role does not allow #{name}."),
          else: error(conn, 404, "not_found", "There is no operation #{name}.")

      tool ->
        context = %{
          actor: actor,
          tenant: tenant,
          context: Ash.PlugHelpers.get_context(conn) || %{}
        }

        case AshAi.Tools.execute(tool, conn.body_params, context, encode?: false) do
          {:ok, result, _raw_result} -> json(conn, result)
          {:error, message} -> error(conn, 422, "operation_failed", message)
        end
    end
  end

  @doc "Returns the OpenAPI description of the API."
  @spec open_api(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def open_api(conn, _params), do: json(conn, OpenApi.spec(FirmowidWeb.Core.Endpoint.url()))

  defp error(conn, status, error, message), do: conn |> put_status(status) |> json(%{error: error, message: message})
end
