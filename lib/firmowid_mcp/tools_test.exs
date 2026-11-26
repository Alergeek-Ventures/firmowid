defmodule FirmowidMcp.ToolsTest do
  @moduledoc """
  The tools an MCP client sees follow the billing plan: a Free plan company uses the
  tools its plan includes, and a tool only a paid plan adds is not listed nor callable.
  """

  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias FirmowidMcp.Router

  test "a Free plan company uses the tools of its plan and does not see the paid ones" do
    user = user_fixture(%{role: :invoicing})

    assert %{"isError" => false} = call(user, "tools/call")
    assert %{"tools" => [%{"name" => "list_sales_invoices"}]} = call(user, "tools/list")
  end

  test "a tool only a paid plan includes is unknown to the Free plan" do
    user = user_fixture()

    assert %{"code" => -32_602, "message" => "Tool not found: create_leave_request"} =
             call(user, "tools/call", "create_leave_request")
  end

  test "a paid plan company sees the tools of its paid features" do
    user = user_fixture(%{plan: :przedsiebiorca})

    assert %{"tools" => tools} = call(user, "tools/list")
    assert "create_leave_request" in Enum.map(tools, & &1["name"])
  end

  defp call(user, method, tool \\ "list_sales_invoices") do
    params =
      if method == "tools/call",
        do: %{"name" => tool, "arguments" => %{}},
        else: %{}

    conn =
      :post
      |> Plug.Test.conn("/", %{
        "jsonrpc" => "2.0",
        "id" => "tools",
        "method" => method,
        "params" => params
      })
      |> put_req_header("mcp-protocol-version", "2025-03-26")
      |> Ash.PlugHelpers.set_actor(user)
      |> Ash.PlugHelpers.set_tenant(user.member.organization_id)
      |> Router.call(Router.init(tools: [:list_sales_invoices, :create_leave_request], mcp_resources: []))

    assert conn.status == 200, conn.resp_body
    response = Jason.decode!(conn.resp_body)
    response["result"] || response["error"]
  end
end
