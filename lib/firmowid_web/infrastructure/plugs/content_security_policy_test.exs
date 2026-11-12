defmodule FirmowidWeb.Infrastructure.Plugs.ContentSecurityPolicyTest do
  use FirmowidWeb.ConnCase, async: true

  test "allows the layout's inline script by the nonce sent in the policy", %{conn: conn} do
    conn = get(conn, ~p"/zaloguj")

    # Either header, so that enforcing the policy stays a configuration change.
    [nonce] =
      Enum.find_value(conn.resp_headers, fn {name, value} ->
        name in ["content-security-policy", "content-security-policy-report-only"] &&
          Regex.run(~r/script-src [^;]*'nonce-([^']+)'/, value, capture: :all_but_first)
      end)

    assert conn
           |> html_response(200)
           |> LazyHTML.from_document()
           |> LazyHTML.query("head script[nonce]")
           |> LazyHTML.attribute("nonce") == [nonce]

    refute get(build_conn(), ~p"/zaloguj").assigns.csp_nonce == nonce
  end
end
