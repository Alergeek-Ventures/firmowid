defmodule FirmowidWeb.Auth.Utilities.ConsentOrganizationTest do
  @moduledoc "Checks that MCP OAuth grants work in the organization chosen on the consent screen."

  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias AshAuthentication.Oauth2Server.Authorize
  alias AshAuthentication.Oauth2Server.PKCE
  alias AshAuthentication.Oauth2Server.Register
  alias AshAuthentication.Oauth2Server.Token
  alias Firmowid.Core
  alias Firmowid.Oauth2Server

  @redirect_uri "https://example.com/oauth/callback"

  setup do
    # The user works in the admin's organization and owns a second one, the default.
    admin = admin_fixture()
    first_id = admin.member.organization_id
    user = user_in_org_fixture(first_id)

    second =
      Core.create_organization!(%{nip: unique_nip(), name: "Druga firma", owner_name: "Druga"},
        actor: user
      )

    {:ok, client, _response} =
      Register.register(Oauth2Server, %{
        "client_name" => "Consent organization #{System.unique_integer([:positive])}",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    %{admin: admin, user: user, client: client, first_id: first_id, second_id: second.id}
  end

  test "the client works in the organization picked on the consent screen, also after a refresh",
       context do
    %{user: user, first_id: first_id, second_id: second_id} = context
    verifier = verifier()
    {conn, html} = consent_screen(context, verifier)

    assert html =~ "Druga firma"
    assert html =~ ~s(value="#{first_id}")
    assert [_, checked_id] = Regex.run(~r/value="([^"]+)"\s+checked/, html)
    assert checked_id == second_id

    tokens = conn |> approve(html, first_id) |> exchange_code(context, verifier)
    assert mcp_tenant(tokens["access_token"]) == first_id

    refreshed = refresh(tokens["refresh_token"], context)
    assert mcp_tenant(refreshed["access_token"]) == first_id
    refute Authorize.consented?(Oauth2Server, user, context.client, "mcp", tenant: second_id)
  end

  test "an approval for a foreign or archived organization is rejected", context do
    %{admin: admin, user: user, first_id: first_id} = context
    foreign_id = admin_fixture().member.organization_id
    Core.archive_member!(Core.load_member(user, first_id).member, actor: admin, tenant: first_id)
    {conn, html} = consent_screen(context, verifier())

    for organization_id <- [foreign_id, first_id] do
      conn = conn |> recycle() |> post("/oauth/authorize", approval(html, organization_id))
      assert conn.status == 400
      assert %{"error" => "invalid_request"} = json_response(conn, 400)
    end

    assert Core.OauthAuthorizationCode.list!(%{user_id: user.id}, authorize?: false) == []
  end

  test "archiving the member revokes only the grants for its organization and those without one",
       context do
    %{admin: admin, user: user, client: client, first_id: first_id, second_id: second_id} =
      context

    first = grant(context, first_id)
    second = grant(context, second_id)

    # A grant issued before the organization was chosen works in the default one.
    legacy_verifier = verifier()

    {:ok, legacy} =
      Token.exchange_authorization_code(Oauth2Server, %{
        "code" => Authorize.issue_code!(Oauth2Server, user, validated(client, legacy_verifier)).id,
        "client_id" => client.id,
        "code_verifier" => legacy_verifier
      })

    FirmowidMcp.Utilities.AccessToken.store!(legacy.access_token, user)
    assert mcp_tenant(legacy.access_token) == second_id

    Core.archive_member!(Core.load_member(user, first_id).member, actor: admin, tenant: first_id)

    assert mcp_tenant(first["access_token"]) == 401
    assert %{"error" => "invalid_grant"} = refresh(first["refresh_token"], context, 400)
    assert %{"error" => "invalid_grant"} = refresh(legacy.refresh_token, context, 400)
    assert mcp_tenant(second["access_token"]) == second_id
    assert mcp_tenant(refresh(second["refresh_token"], context)["access_token"]) == second_id
  end

  test "an organization-bound grant never yields a token without its organization", context do
    %{client: client, first_id: first_id} = context

    # Grants passed in the query string, as the OAuth server also reads them.
    verifier = verifier()
    {conn, html} = consent_screen(context, verifier)
    code = approve(conn, html, first_id)

    tokens =
      token_request(
        %{
          "grant_type" => "authorization_code",
          "client_id" => client.id,
          "code_verifier" => verifier
        },
        200,
        "/oauth/token?" <> URI.encode_query(%{"code" => code})
      )

    assert mcp_tenant(tokens["access_token"]) == first_id

    refreshed =
      token_request(
        %{"grant_type" => "refresh_token", "client_id" => client.id},
        200,
        "/oauth/token?" <> URI.encode_query(%{"refresh_token" => tokens["refresh_token"]})
      )

    assert mcp_tenant(refreshed["access_token"]) == first_id

    # An exchange without the grant's organization is rejected.
    verifier = verifier()
    {conn, html} = consent_screen(context, verifier)
    code = approve(conn, html, first_id)

    assert {:error, :invalid_code} =
             Token.exchange_authorization_code(Oauth2Server, %{
               "code" => code,
               "client_id" => client.id,
               "code_verifier" => verifier
             })

    assert {:error, _reason} =
             Token.exchange_refresh_token(Oauth2Server, %{
               "refresh_token" => refreshed["refresh_token"],
               "client_id" => client.id
             })

    assert mcp_tenant(refresh(refreshed["refresh_token"], context)["access_token"]) == first_id
  end

  defp grant(context, organization_id) do
    verifier = verifier()
    {conn, html} = consent_screen(context, verifier)
    conn |> approve(html, organization_id) |> exchange_code(context, verifier)
  end

  defp consent_screen(context, verifier) do
    conn = log_in_user(build_conn(), context.user)

    query = %{
      "client_id" => context.client.id,
      "response_type" => "code",
      "redirect_uri" => @redirect_uri,
      "code_challenge" => PKCE.challenge(verifier),
      "code_challenge_method" => "S256",
      "scope" => "mcp"
    }

    conn = get(conn, "/oauth/authorize?" <> URI.encode_query(query))
    {conn, html_response(conn, 200)}
  end

  defp approve(conn, html, organization_id) do
    conn = conn |> recycle() |> post("/oauth/authorize", approval(html, organization_id))

    %{"code" => code} =
      conn |> redirected_to(302) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    code
  end

  defp approval(html, organization_id) do
    [_, consent_request] = Regex.run(~r/name="consent_request" value="([^"]+)"/, html)

    %{
      "consent_request" => consent_request,
      "action" => "approve",
      "organization_id" => organization_id
    }
  end

  defp exchange_code(code, context, verifier) do
    token_request(%{
      "grant_type" => "authorization_code",
      "code" => code,
      "client_id" => context.client.id,
      "code_verifier" => verifier
    })
  end

  defp refresh(refresh_token, context, status \\ 200) do
    token_request(
      %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token,
        "client_id" => context.client.id
      },
      status
    )
  end

  defp token_request(params, status \\ 200, path \\ "/oauth/token") do
    build_conn() |> post(path, params) |> json_response(status)
  end

  defp validated(client, verifier) do
    {:ok, validated} =
      Authorize.validate_request(Oauth2Server, %{
        "client_id" => client.id,
        "response_type" => "code",
        "redirect_uri" => @redirect_uri,
        "code_challenge" => PKCE.challenge(verifier),
        "code_challenge_method" => "S256",
        "scope" => "mcp"
      })

    validated
  end

  defp verifier, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  # The tenant an MCP request with the access token runs in, or the error status.
  defp mcp_tenant(token) do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("content-type", "application/json")
      |> post(
        "/mcp",
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{
            "protocolVersion" => "2025-03-26",
            "capabilities" => %{},
            "clientInfo" => %{"name" => "consent-organization", "version" => "1"}
          }
        })
      )

    if conn.status == 200, do: Ash.PlugHelpers.get_tenant(conn), else: conn.status
  end
end
