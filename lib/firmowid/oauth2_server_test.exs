defmodule Firmowid.Oauth2ServerTest do
  @moduledoc "Checks OAuth issuance, exchange, and HTTP bearer authentication across leaving the organization."

  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Invalid
  alias AshAuthentication.Oauth2Server.Authorize
  alias AshAuthentication.Oauth2Server.PKCE
  alias AshAuthentication.Oauth2Server.Register
  alias AshAuthentication.Oauth2Server.Token
  alias Firmowid.Core
  alias Firmowid.Core.OauthAuthorizationCode
  alias Firmowid.Core.OauthConsent
  alias Firmowid.Core.OauthRefreshToken
  alias Firmowid.Oauth2Server
  alias FirmowidMcp.Session
  alias FirmowidMcp.Utilities.AccessToken

  @auth_context %{private: %{ash_authentication?: true}}
  @redirect_uri "https://example.com/oauth/callback"

  setup do
    admin = admin_fixture()
    user = user_in_org_fixture(admin.member.organization_id)
    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {:ok, client, _response} =
      Register.register(Oauth2Server, %{
        "client_name" => "Archived member regression #{System.unique_integer([:positive])}",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    {:ok, validated} =
      Authorize.validate_request(Oauth2Server, %{
        "client_id" => client.id,
        "response_type" => "code",
        "redirect_uri" => @redirect_uri,
        "code_challenge" => PKCE.challenge(verifier),
        "code_challenge_method" => "S256",
        "scope" => "mcp",
        "state" => Ash.UUIDv7.generate()
      })

    %{admin: admin, user: user, client: client, verifier: verifier, validated: validated}
  end

  test "active users can consent, exchange, authenticate over HTTP, and rotate", context do
    %{user: user, client: client, validated: validated} = context
    assert user.system_role == :user

    consent = Authorize.grant_consent!(Oauth2Server, user, client, "mcp")
    assert consent.user_id == user.id
    assert Authorize.consented?(Oauth2Server, user, client, "mcp")

    code = Authorize.issue_code!(Oauth2Server, user, validated)
    assert {:ok, tokens} = exchange_code(code, context)
    assert {:error, :reuse} = exchange_code(code, context)
    assert_authenticated(tokens.access_token, user)

    assert {:ok, rotated} = exchange_refresh(tokens.refresh_token, client)
    refute rotated.refresh_token == tokens.refresh_token
    assert_authenticated(rotated.access_token, user)
    assert {:error, :reuse} = exchange_refresh(tokens.refresh_token, client)
    assert {:error, :revoked} = exchange_refresh(rotated.refresh_token, client)
  end

  for operation <- [:change, :reset] do
    test "password #{operation} denies existing HTTP OAuth JWTs and widgets only for that user",
         context do
      %{user: user, admin: admin, validated: validated} = context
      other = user_in_org_fixture(admin.member.organization_id)
      tokens = http_exchange(user, validated, context)
      other_tokens = http_exchange(other, validated, context)
      old_widget = widget(tokens["access_token"])
      other_widget = widget(other_tokens["access_token"])
      resource_uri = "ui://oauth-revocation"

      assert {:ok, _} = Session.authorize(old_widget, resource_uri)
      assert {:ok, _} = Session.authorize(other_widget, resource_uri)

      rotated =
        build_conn()
        |> post("/oauth/token", %{
          grant_type: "refresh_token",
          refresh_token: tokens["refresh_token"],
          client_id: context.client.id
        })
        |> json_response(200)

      assert_authenticated(rotated["access_token"], user)
      rotated_widget = widget(rotated["access_token"])
      assert {:ok, _} = Session.authorize(rotated_widget, resource_uri)
      assert {:ok, _} = revoke_password(unquote(operation), user)

      for token <- [tokens["access_token"], rotated["access_token"]] do
        assert mcp_request(token).status == 401
      end

      assert {:error, :unauthorized} = Session.authorize(old_widget, resource_uri)
      assert {:error, :unauthorized} = Session.authorize(rotated_widget, resource_uri)
      assert_authenticated(other_tokens["access_token"], other)
      assert {:ok, _} = Session.authorize(other_widget, resource_uri)
      assert {:error, :revoked} = exchange_refresh(rotated["refresh_token"], context.client)
    end
  end

  test "a valid native JWT without registration requires reauthentication", %{
    user: user,
    client: client
  } do
    {:ok, token, _claims} =
      AshAuthentication.Oauth2Server.Jwt.mint(Oauth2Server,
        sub: user.id,
        client_id: client.id,
        scope: "mcp"
      )

    assert mcp_request(token).status == 401
  end

  test "authorization rejects ambiguous loopback redirect authorities", %{client: client} do
    Ash.Seed.update!(client, %{redirect_uris: ["http://127.0.0.1/callback"]})

    for redirect_uri <- [
          "http://attacker.invalid\\@127.0.0.1/callback",
          "http://attacker.invalid\\@localhost/callback",
          "http://127.0.0.1/callback#fragment"
        ] do
      params = %{
        "client_id" => client.id,
        "redirect_uri" => redirect_uri,
        "response_type" => "unsupported"
      }

      conn = get(build_conn(), "/oauth/authorize?" <> URI.encode_query(params))
      assert conn.status == 400
      assert get_resp_header(conn, "location") == []
    end
  end

  test "authorization still allows ephemeral loopback ports", %{client: client} do
    Ash.Seed.update!(client, %{
      redirect_uris: ["http://127.0.0.1/callback", "http://[::1]/callback"]
    })

    for host <- ["127.0.0.1", "localhost", "[::1]"] do
      params = %{
        "client_id" => client.id,
        "redirect_uri" => "http://#{host}:54321/callback",
        "response_type" => "unsupported"
      }

      conn = get(build_conn(), "/oauth/authorize?" <> URI.encode_query(params))
      assert conn.status == 302
      [location] = get_resp_header(conn, "location")

      assert location =~
               "http://#{if host == "localhost", do: "127.0.0.1", else: host}:54321/callback?"
    end
  end

  test "an account without an organization gets no issuance or consent, even with a stale user",
       context do
    %{user: user, client: client, validated: validated} = context
    consent = Authorize.grant_consent!(Oauth2Server, user, client, "mcp")
    Ash.Seed.update!(user.member, %{archived_at: Date.utc_today()})

    assert_raise Invalid, fn ->
      Authorize.issue_code!(Oauth2Server, user, validated)
    end

    assert_raise Invalid, fn ->
      Authorize.grant_consent!(Oauth2Server, user, client, "mcp")
    end

    assert {:error, _} =
             OauthRefreshToken.issue(refresh_attributes(user, client), context: @auth_context)

    assert [] = OauthAuthorizationCode.list!(%{user_id: user.id}, context: @auth_context)
    assert [existing_consent] = OauthConsent.list!(%{user_id: user.id}, context: @auth_context)
    assert existing_consent.granted_at == consent.granted_at
    assert [] = OauthRefreshToken.list!(%{user_id: user.id}, context: @auth_context)
  end

  test "an account without an organization gets no code consumption or refresh rotation",
       context do
    %{user: user, client: client, validated: validated} = context
    code = Authorize.issue_code!(Oauth2Server, user, validated)
    exchanged_code = Authorize.issue_code!(Oauth2Server, user, validated)
    assert {:ok, tokens} = exchange_code(exchanged_code, context)
    Ash.Seed.update!(user.member, %{archived_at: Date.utc_today()})

    assert {:error, _} = OauthAuthorizationCode.consume(code, context: @auth_context)
    assert {:error, :invalid_code} = exchange_code(code, context)
    assert {:error, :invalid_refresh} = exchange_refresh(tokens.refresh_token, client)

    assert [%{consumed_at: nil}] =
             OauthAuthorizationCode.list!(%{user_id: user.id},
               query: [filter: [id: code.id]],
               context: @auth_context
             )

    assert [refresh] = OauthRefreshToken.list!(%{user_id: user.id}, context: @auth_context)
    assert is_nil(refresh.rotated_at)
    assert is_nil(refresh.rotated_to_id)
    assert is_nil(refresh.revoked_at)

    assert {:error, _} =
             OauthRefreshToken.rotate(refresh, %{rotated_to_id: Ash.UUIDv7.generate()}, context: @auth_context)

    assert_without_organization(tokens.access_token)
  end

  test "archiving the member invalidates outstanding grants without affecting another user",
       context do
    %{admin: admin, user: user, client: client, validated: validated} = context
    other = user_in_org_fixture(admin.member.organization_id)
    Authorize.grant_consent!(Oauth2Server, user, client, "mcp")
    code = Authorize.issue_code!(Oauth2Server, user, validated)
    exchanged_code = Authorize.issue_code!(Oauth2Server, user, validated)
    assert {:ok, tokens} = exchange_code(exchanged_code, context)
    other_code = Authorize.issue_code!(Oauth2Server, other, validated)
    assert {:ok, other_tokens} = exchange_code(other_code, context)
    assert_authenticated(tokens.access_token, user)

    archived =
      Core.archive_member!(user.member, actor: admin, tenant: admin.member.organization_id)

    assert archived.archived_at
    assert Core.load_member(user).member == nil

    assert {:error, :invalid_code} = exchange_code(code, context)
    assert {:error, :revoked} = exchange_refresh(tokens.refresh_token, client)
    assert_without_organization(tokens.access_token)
    assert_authenticated(other_tokens.access_token, other)
    assert {:ok, _tokens} = exchange_refresh(other_tokens.refresh_token, client)
    refute Authorize.consented?(Oauth2Server, user, client, "mcp")

    Core.unarchive_member!(archived, actor: admin, tenant: admin.member.organization_id)
    assert {:error, :invalid_code} = exchange_code(code, context)
    assert {:error, :revoked} = exchange_refresh(tokens.refresh_token, client)
  end

  test "re-archiving an old membership keeps the grants of the organization the account works in now",
       context do
    %{admin: admin, user: user, client: client, validated: validated} = context
    opts = [actor: admin, tenant: admin.member.organization_id]
    archived = Core.archive_member!(user.member, opts)

    Core.set_organization!(
      user,
      %{organization_id: admin_fixture().member.organization_id, role: :employee},
      authorize?: false
    )

    user = Core.load_member(user)
    code = Authorize.issue_code!(Oauth2Server, user, validated)
    assert {:ok, tokens} = exchange_code(code, context)

    # A stale view of the old membership still showing it as active.
    assert {:error, %Invalid{}} = Core.archive_member(%{archived | archived_at: nil}, opts)

    assert_authenticated(tokens.access_token, user)
    assert {:ok, _tokens} = exchange_refresh(tokens.refresh_token, client)
  end

  defp exchange_code(code, context) do
    Oauth2Server
    |> Token.exchange_authorization_code(%{
      "code" => code.id,
      "client_id" => context.client.id,
      "redirect_uri" => @redirect_uri,
      "code_verifier" => context.verifier
    })
    |> register_exchange()
  end

  defp exchange_refresh(raw, client) do
    Oauth2Server
    |> Token.exchange_refresh_token(%{
      "refresh_token" => raw,
      "client_id" => client.id
    })
    |> register_exchange()
  end

  # Library-level assertions bypass HTTP registration deliberately.
  defp register_exchange({:ok, tokens} = result) do
    {:ok, %{"sub" => id}} = AshAuthentication.Jwt.peek(tokens.access_token)
    AccessToken.store!(tokens.access_token, Core.get_user!(id, context: @auth_context))
    result
  end

  defp register_exchange(result), do: result

  defp http_exchange(user, validated, context) do
    code = Authorize.issue_code!(Oauth2Server, user, validated)

    build_conn()
    |> post("/oauth/%74oken", %{
      grant_type: "authorization_code",
      code: code.id,
      client_id: context.client.id,
      redirect_uri: @redirect_uri,
      code_verifier: context.verifier
    })
    |> json_response(200)
  end

  defp widget(token) do
    conn = mcp_request(token)
    assert conn.status == 200
    Session.issue(conn, "ui://oauth-revocation", %{})
  end

  defp revoke_password(:change, user) do
    Core.change_password(
      user,
      %{
        current_password: valid_user_password(),
        password: String.reverse(valid_user_password()),
        password_confirmation: String.reverse(valid_user_password())
      },
      actor: user
    )
  end

  defp revoke_password(:reset, user) do
    strategy = AshAuthentication.Info.strategy!(Core.User, :password)
    {:ok, token} = AshAuthentication.Strategy.Password.reset_token_for(strategy, user)

    AshAuthentication.Strategy.action(
      strategy,
      :reset,
      %{
        "reset_token" => token,
        "password" => String.reverse(valid_user_password())
      },
      []
    )
  end

  defp refresh_attributes(user, client) do
    id = Ash.UUIDv7.generate()

    %{
      id: id,
      chain_id: id,
      token_hash: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
      client_id: client.id,
      user_id: user.id,
      scope: "mcp",
      resource_uri: Oauth2Server.resource_url(),
      expires_at: DateTime.shift(DateTime.utc_now(), minute: 5)
    }
  end

  defp assert_authenticated(token, user) do
    conn = mcp_request(token)
    assert conn.status == 200
    assert %{"result" => %{"protocolVersion" => "2025-03-26"}} = json_response(conn, 200)
    assert Ash.PlugHelpers.get_actor(conn).id == user.id
    assert Ash.PlugHelpers.get_tenant(conn) == user.member.organization_id
    assert conn.assigns.oauth_claims["scope"] == "mcp"
  end

  defp assert_without_organization(token) do
    conn = mcp_request(token)
    assert conn.status == 401
    assert conn.halted
    assert %{"message" => "Organization required"} = json_response(conn, 401)
  end

  defp mcp_request(token) do
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
          "clientInfo" => %{"name" => "archive-regression", "version" => "1"}
        }
      })
    )
  end
end
