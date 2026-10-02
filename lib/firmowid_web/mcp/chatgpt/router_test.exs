defmodule FirmowidWeb.Mcp.Chatgpt.RouterTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias FirmowidWeb.Mcp.Chatgpt.Router

  @uri "ui://firmowid/chatgpt/sessions.html"

  test "dedicated endpoint requires OAuth and does not shadow the original endpoint", %{
    conn: conn
  } do
    for path <- ["/mcp-chatgpt", "/mcp"] do
      response = post(conn, path, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
      assert response.status == 401
    end

    route =
      Phoenix.Router.route_info(FirmowidWeb.Core.Router, "POST", "/mcp-chatgpt", "localhost")

    assert route.plug == Router
    assert route.pipe_through == [:mcp]
  end

  test "native allowlist, UI binding, read-only annotations and OAuth descriptors" do
    result = rpc("tools/list")["result"]
    assert [tool] = result["tools"]
    assert tool["name"] == "chatgpt_list_sessions"
    assert tool["_meta"]["ui"]["resourceUri"] == @uri

    assert tool["annotations"] == %{
             "readOnlyHint" => true,
             "destructiveHint" => false,
             "openWorldHint" => false
           }

    assert tool["securitySchemes"] == [%{"type" => "oauth2", "scopes" => ["mcp"]}]
    assert tool["_meta"]["securitySchemes"] == tool["securitySchemes"]
    assert tool["inputSchema"]["properties"]["limit"]["maximum"] == 50
    assert rpc("tools/call", %{"name" => "start_session"})["error"]

    assert [resource] = rpc("resources/list")["result"]["resources"]
    assert resource["uri"] == @uri
    assert resource["mimeType"] == "text/html;profile=mcp-app"
    assert [content] = rpc("resources/read", %{"uri" => @uri})["result"]["contents"]
    assert content["_meta"]["ui"]["csp"]["connectDomains"] == []
    assert content["_meta"]["ui"]["csp"]["resourceDomains"] == []
    assert content["text"] =~ "ui/initialize"
  end

  test "bounded authorized preview includes project and duration, isolates actor and tenant" do
    user = user_fixture()
    colleague = user_fixture(%{organization_id: user.organization_id})
    outsider = user_fixture()

    for actor <- [user, colleague, outsider] do
      session_fixture(%{
        organization_id: actor.organization_id,
        user_id: actor.id,
        title: actor.email,
        start_datetime: ~U[2025-04-01 09:00:00Z],
        end_datetime: ~U[2025-04-01 10:00:00Z]
      })
    end

    params = %{"name" => "chatgpt_list_sessions", "arguments" => %{"input" => %{}, "limit" => 1}}
    result = rpc("tools/call", params, user)["result"]
    refute result["isError"]
    preview = result["structuredContent"]

    assert [%{"title" => title, "duration" => 3600, "project" => %{"name" => _}}] =
             preview["sessions"]

    assert title == to_string(user.email)
    assert preview["limit"] == 1
    assert preview["possibly_truncated"]
    assert Jason.decode!(hd(result["content"])["text"]) == preview

    [tool] = rpc("tools/list")["result"]["tools"]
    schema = tool["outputSchema"]
    assert schema["type"] == "object"
    assert Enum.sort(schema["required"]) == Enum.sort(Map.keys(preview))

    assert schema["properties"]["limit"] == %{
             "type" => "integer",
             "minimum" => 1,
             "maximum" => 50
           }

    assert schema["properties"]["after_date"]["type"] == ["string", "null"]
    assert schema["properties"]["possibly_truncated"]["type"] == "boolean"
    session_schema = schema["properties"]["sessions"]["items"]

    assert Enum.sort(session_schema["required"]) ==
             Enum.sort(["title", "start_datetime", "end_datetime", "duration", "project"])

    session = hd(preview["sessions"])
    assert Enum.sort(session_schema["required"]) == Enum.sort(Map.keys(session))
    assert session_schema["additionalProperties"] == false
    assert session_schema["properties"]["duration"]["type"] == "integer"
    assert session_schema["properties"]["end_datetime"]["type"] == ["string", "null"]
    project_schema = session_schema["properties"]["project"]
    assert Map.keys(session["project"]) == ["name"]
    assert project_schema["type"] == ["object", "null"]
    assert project_schema["additionalProperties"] == false
    assert project_schema["properties"]["name"]["type"] == "string"

    filtered = put_in(params, ["arguments", "input"], %{"after_date" => "2025-04-02"})
    assert rpc("tools/call", filtered, user)["result"]["structuredContent"]["sessions"] == []

    for arguments <- [
          %{"limit" => 51},
          %{"limit" => 0},
          %{"filter" => %{}},
          %{"input" => %{"user_id" => colleague.id}}
        ] do
      rejected = rpc("tools/call", Map.put(params, "arguments", arguments), user)["result"]
      assert rejected["isError"]
    end
  end

  test "running preview restores null end and excludes native fields from both result forms" do
    user = user_fixture()

    session_fixture(%{
      organization_id: user.organization_id,
      user_id: user.id,
      start_datetime: DateTime.shift(DateTime.utc_now(), minute: -5)
    })

    result = rpc("tools/call", %{"name" => "chatgpt_list_sessions"}, user)["result"]
    assert result["isError"] == false
    assert [session] = result["structuredContent"]["sessions"]

    assert session |> Map.keys() |> Enum.sort() ==
             Enum.sort(["title", "start_datetime", "end_datetime", "duration", "project"])

    assert session["end_datetime"] == nil
    assert is_integer(session["duration"])
    assert session["duration"] >= 0
    assert Map.keys(session["project"]) == ["name"]
    assert Jason.decode!(hd(result["content"])["text"]) == result["structuredContent"]
  end

  test "serialized projection restores an absent project without making non-null fields nullable" do
    serialized = %{
      "title" => "Session",
      "start_datetime" => "2025-04-01T09:00:00Z",
      "duration" => 300,
      "id" => "private-id",
      "inserted_at" => "private-timestamp",
      "updated_at" => "private-timestamp",
      "is_remote" => true,
      "lockdown" => false
    }

    assert Router.session_preview(serialized) ==
             serialized
             |> Map.take(["title", "start_datetime", "duration"])
             |> Map.merge(%{"end_datetime" => nil, "project" => nil})

    [tool] = rpc("tools/list")["result"]["tools"]
    properties = tool["outputSchema"]["properties"]["sessions"]["items"]["properties"]
    assert properties["title"]["type"] == "string"
    assert properties["start_datetime"]["type"] == "string"
    assert properties["project"]["type"] == ["object", "null"]
  end

  test "explicit limit 50 is not truncated to the default 25" do
    user = user_fixture()
    project = project_fixture(%{organization_id: user.organization_id})
    user_project_fixture(user.id, project.id, user.organization_id)

    for index <- 0..50 do
      start = DateTime.shift(~U[2025-04-01 00:00:00Z], hour: index * 2)

      Firmowid.Ash.Timetracker.Session.create!(
        %{
          title: "Session #{index}",
          project_id: project.id,
          user_id: user.id,
          start_datetime: start,
          end_datetime: DateTime.shift(start, hour: 1)
        },
        actor: user,
        tenant: user.organization_id
      )
    end

    for {arguments, expected_limit} <- [
          {%{"input" => %{}}, 25},
          {%{"input" => %{}, "limit" => 1}, 1},
          {%{"input" => %{}, "limit" => 50}, 50}
        ] do
      result =
        rpc("tools/call", %{"name" => "chatgpt_list_sessions", "arguments" => arguments}, user)[
          "result"
        ]

      assert result["isError"] == false
      preview = result["structuredContent"]
      assert length(preview["sessions"]) == expected_limit
      assert preview["limit"] == expected_limit
      assert preview["possibly_truncated"] == true
      assert hd(preview["sessions"])["title"] == "Session 50"
    end
  end

  defp rpc(method, params \\ %{}, actor \\ nil) do
    meta = %{
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientInfo" => %{"name" => "regression-test", "version" => "1"},
      "io.modelcontextprotocol/clientCapabilities" => %{
        "extensions" => %{
          "io.modelcontextprotocol/ui" => %{"mimeTypes" => ["text/html;profile=mcp-app"]}
        }
      }
    }

    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => Map.put(params, "_meta", meta)
    }

    conn =
      :post
      |> Plug.Test.conn("/", Jason.encode!(body))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("mcp-protocol-version", "2026-07-28")
      |> Plug.Conn.put_req_header("mcp-method", method)
      |> Plug.Conn.put_req_header("mcp-name", params["name"] || params["uri"] || "")
      |> Ash.PlugHelpers.set_actor(actor)
      |> Ash.PlugHelpers.set_tenant(actor && actor.organization_id)
      |> Router.call(Router.init([]))

    Jason.decode!(conn.resp_body)
  end
end
