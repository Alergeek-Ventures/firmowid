defmodule FirmowidMcp.PlanGateTest do
  @moduledoc "A company without AI clients in its plan gets a readable refusal of every tool call."

  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias FirmowidMcp.Router
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  test "a tool call of a Free plan company is refused with the plan and the address, the tool list is not" do
    user = user_fixture(%{role: :invoicing})

    assert %{"isError" => true, "content" => [%{"text" => text}]} = call(user, "tools/call")
    assert text =~ "Entrepreneur plan"
    assert text =~ SettingsNavigation.canonical_path(:subscription)
    assert text =~ "http"

    assert %{"tools" => [_ | _]} = call(user, "tools/list")
  end

  test "a tool the plan's own gate hides is refused the same way, not as an unknown tool" do
    user = user_fixture()

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             call(user, "tools/call", "create_leave_request")

    assert text =~ "Entrepreneur plan"
  end

  test "the same call works once the company has the plan" do
    user = user_fixture(%{role: :invoicing, plan: :przedsiebiorca})

    assert %{"isError" => false} = call(user, "tools/call")
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
        "id" => "plan",
        "method" => method,
        "params" => params
      })
      |> put_req_header("mcp-protocol-version", "2025-03-26")
      |> Ash.PlugHelpers.set_actor(user)
      |> Ash.PlugHelpers.set_tenant(user.member.organization_id)
      |> Router.call(Router.init(tools: [:list_sales_invoices, :create_leave_request], mcp_resources: []))

    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)["result"]
  end
end
