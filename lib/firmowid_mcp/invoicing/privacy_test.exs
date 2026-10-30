defmodule FirmowidMcp.Invoicing.PrivacyTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Invoicing.SalesInvoice
  alias FirmowidMcp.Router

  for selector <- [
        "buyer_pesel",
        "+buyer_pesel",
        "id,-buyer_pesel",
        "effective_buyer_pesel",
        "pesel",
        "reference_invoice.buyer_pesel",
        ["buyer_", "pesel"]
      ] do
    @tag selector: selector
    test "rejects PESEL sort selector #{inspect(selector)} in the decorated MCP transport", %{
      selector: selector
    } do
      assert_private_arguments(%{
        "limit" => 1,
        "sort" => [%{"field" => selector, "direction" => "asc"}]
      })
    end
  end

  test "rejects PESEL aggregate selectors in the decorated MCP transport" do
    assert_private_arguments(%{
      "result_type" => %{"aggregate" => "min", "field" => "buyer_pesel"}
    })
  end

  test "preserves sorting by a non-sensitive invoice field" do
    assert_private_arguments(
      %{"limit" => 1, "sort" => [%{"field" => "issue_date", "direction" => "asc"}]},
      false
    )
  end

  defp assert_private_arguments(arguments, error? \\ true) do
    user = user_fixture(%{role: :invoicing})

    {:ok, token, claims} =
      AshAuthentication.Oauth2Server.Jwt.mint(Firmowid.Oauth2Server,
        sub: user.id,
        client_id: Ash.UUIDv7.generate(),
        scope: "mcp"
      )

    FirmowidMcp.Utilities.AccessToken.store!(token, user)

    Ash.Seed.seed!(SalesInvoice, %{
      organization_id: user.member.organization_id,
      issue_date: Date.utc_today(),
      sale_date: Date.utc_today(),
      due_date: Date.utc_today(),
      currency: "PLN",
      buyer_type: :individual,
      buyer_pesel: "44051401458"
    })

    opts = Router.init(tools: [:list_sales_invoices], mcp_resources: [])

    response =
      :post
      |> Plug.Test.conn("/", %{
        "jsonrpc" => "2.0",
        "id" => "privacy",
        "method" => "tools/call",
        "params" => %{
          "_meta" => %{
            "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities" => %{},
            "io.modelcontextprotocol/clientInfo" => %{"name" => "privacy-test", "version" => "1"}
          },
          "name" => "list_sales_invoices",
          "arguments" => arguments
        }
      })
      |> Plug.Conn.put_req_header("mcp-protocol-version", "2026-07-28")
      |> Plug.Conn.put_req_header("mcp-method", "tools/call")
      |> Plug.Conn.put_req_header("mcp-name", "list_sales_invoices")
      |> Plug.Conn.assign(:oauth_claims, claims)
      |> Ash.PlugHelpers.set_actor(user)
      |> FirmowidMcp.Utilities.Authenticate.call([])
      |> Router.call(opts)

    assert response.status == 200, response.resp_body
    result = Jason.decode!(response.resp_body)["result"]
    refute response.resp_body =~ "44051401458", inspect(result)

    for key <- ["start_keyset", "end_keyset"],
        cursor = get_in(result, ["structuredContent", key]),
        is_binary(cursor) do
      refute Base.decode64!(cursor) =~ "44051401458"
    end

    assert result["isError"] == error?, inspect(result)
  end
end
