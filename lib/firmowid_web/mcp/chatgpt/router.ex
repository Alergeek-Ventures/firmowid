defmodule FirmowidWeb.Mcp.Chatgpt.Router do
  @moduledoc """
  Read-only ChatGPT prototype adapter around the native AshAi MCP transport.

  Authentication is owned by the shared router pipeline. This adapter only
  bounds inputs and fills descriptor/result fields missing from AshAi 1.0.3.
  """
  @behaviour Plug

  import Plug.Conn

  alias AshAi.Mcp.Router

  @doc "Initializes the native transport with an explicit tool and resource allowlist."
  @spec init(keyword()) :: keyword()
  def init(_opts) do
    Router.init(
      otp_app: :firmowid,
      tools: [:chatgpt_list_sessions],
      mcp_resources: [:chatgpt_sessions],
      tool_argument_transformer: &__MODULE__.bound_arguments/3
    )
  end

  @doc "Delegates protocol handling, decorating only this endpoint's JSON responses."
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> register_before_send(&decorate_response/1)
    |> Router.call(opts)
  end

  @doc "Rejects undeclared inputs and enforces a positive, bounded preview size."
  @spec bound_arguments(AshAi.Tool.t(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def bound_arguments(_tool, arguments, _context) when is_map(arguments) do
    limit = Map.get(arguments, "limit", 25)
    input = Map.get(arguments, "input", %{})

    if Enum.all?(Map.keys(arguments), &(&1 in ["input", "limit"])) and
         is_map(input) and Enum.all?(Map.keys(input), &(&1 == "after_date")) and
         is_integer(limit) and limit in 1..50 do
      {:ok, arguments |> Map.put("limit", limit) |> Map.put("input", input)}
    else
      {:error, "Only input.after_date and an integer limit between 1 and 50 are accepted."}
    end
  end

  def bound_arguments(_tool, _arguments, _context), do: {:error, "Expected an argument object."}

  defp decorate_response(conn) do
    case Jason.decode(conn.resp_body || "") do
      {:ok, body} -> %{conn | resp_body: Jason.encode!(decorate(body, conn.body_params))}
      _ -> conn
    end
  end

  defp decorate(responses, requests) when is_list(responses) do
    Enum.map(responses, fn response ->
      request = Enum.find(requests["_json"] || [], &(&1["id"] == response["id"])) || %{}
      decorate(response, request)
    end)
  end

  defp decorate(%{"result" => %{"tools" => tools}} = response, _request) do
    tools =
      Enum.map(tools, fn tool ->
        tool
        |> Map.put("title", "Moje sesje pracy")
        |> Map.put("outputSchema", output_schema())
        |> put_in(["inputSchema", "properties", "limit", "minimum"], 1)
        |> put_in(["inputSchema", "properties", "limit", "maximum"], 50)
        |> Map.put("securitySchemes", tool["_meta"]["securitySchemes"])
        |> Map.put("annotations", %{
          "readOnlyHint" => true,
          "destructiveHint" => false,
          "openWorldHint" => false
        })
      end)

    put_in(response, ["result", "tools"], tools)
  end

  defp decorate(%{"result" => %{"isError" => false, "content" => [content]}} = response, request) do
    case Jason.decode(content["text"]) do
      {:ok, sessions} when is_list(sessions) ->
        arguments = get_in(request, ["params", "arguments"]) || %{}
        limit = Map.get(arguments, "limit", 25)

        preview = %{
          "sessions" => Enum.map(sessions, &session_preview/1),
          "limit" => limit,
          "after_date" => get_in(arguments, ["input", "after_date"]),
          "possibly_truncated" => length(sessions) >= limit
        }

        response
        |> put_in(["result", "structuredContent"], preview)
        |> put_in(["result", "content"], [%{"type" => "text", "text" => Jason.encode!(preview)}])

      _ ->
        response
    end
  end

  defp decorate(response, _request), do: response

  @doc "Projects a serialized session onto the public preview, restoring omitted nullable fields."
  @spec session_preview(map()) :: map()
  def session_preview(session) do
    session
    |> Map.take(["title", "start_datetime", "duration"])
    |> Map.put("end_datetime", Map.get(session, "end_datetime"))
    |> Map.put("project", project_preview(Map.get(session, "project")))
  end

  defp project_preview(nil), do: nil
  defp project_preview(project), do: Map.take(project, ["name"])

  defp output_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["sessions", "limit", "after_date", "possibly_truncated"],
      "properties" => %{
        "sessions" => %{
          "type" => "array",
          "maxItems" => 50,
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["title", "start_datetime", "end_datetime", "duration", "project"],
            "properties" => %{
              "title" => %{"type" => "string"},
              "start_datetime" => %{"type" => "string", "format" => "date-time"},
              "end_datetime" => %{"type" => ["string", "null"], "format" => "date-time"},
              "duration" => %{"type" => "integer"},
              "project" => %{
                "type" => ["object", "null"],
                "additionalProperties" => false,
                "required" => ["name"],
                "properties" => %{"name" => %{"type" => "string"}}
              }
            }
          }
        },
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 50},
        "after_date" => %{"type" => ["string", "null"], "format" => "date"},
        "possibly_truncated" => %{"type" => "boolean"}
      }
    }
  end
end
