defmodule FirmowidWeb.Api.Utilities.OpenApi do
  @moduledoc """
  Builds the OpenAPI description of the public API from its AshAi tools, with the input and
  output schemas AshAi gives the MCP server: one `POST /api/v1/<tool>` operation per tool, whose
  JSON body is the tool's arguments.
  """

  alias FirmowidWeb.Api.Utilities.Tools

  @error_schema %{
    "type" => "object",
    "properties" => %{"error" => %{"type" => "string"}, "message" => %{"type" => "string"}}
  }

  @doc "Returns the OpenAPI 3.1 document of the API served at `base_url`."
  @spec spec(String.t()) :: map()
  def spec(base_url) do
    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "Firmowid API",
        "version" => "1",
        "description" =>
          "The operations of the Firmowid MCP server, called with an API key from the \"API keys\" settings page. " <>
            "A key works in its company with its role, so it may call only the operations that role allows."
      },
      "servers" => [%{"url" => base_url <> "/api/v1"}],
      "security" => [%{"apiKey" => []}],
      "components" => %{
        "securitySchemes" => %{
          "apiKey" => %{
            "type" => "http",
            "scheme" => "bearer",
            "description" => "`Authorization: Bearer firmowid_…` (personal key) or `firmowid_org_…` (company key)."
          }
        }
      },
      "paths" => Map.new(Tools.documented(), &{"/#{&1.name}", %{"post" => operation(&1)}})
    }
  end

  defp operation(tool) do
    %{
      "operationId" => Atom.to_string(tool.name),
      # Grouped by the domain the operation belongs to, such as Invoicing or Finances.
      "tags" => [tool.domain |> Module.split() |> List.last()],
      "summary" => tool.title || tool.annotations[:title] || Atom.to_string(tool.name),
      "description" => AshAi.Tools.description(tool),
      "requestBody" => %{
        "required" => true,
        "content" => %{
          "application/json" => %{"schema" => AshAi.Tools.parameter_schema(tool, strict: false)}
        }
      },
      "responses" => %{
        "200" => %{
          "description" => "The result, as the MCP tool returns it.",
          "content" => %{
            "application/json" => %{"schema" => AshAi.Tool.OutputSchema.for_tool(tool) || %{}}
          }
        },
        "401" => error("A valid API key is required."),
        "403" => error("The key's role does not allow the operation."),
        "422" => error("The operation failed, for example on invalid input; `message` says why.")
      }
    }
  end

  defp error(description),
    do: %{"description" => description, "content" => %{"application/json" => %{"schema" => @error_schema}}}
end
