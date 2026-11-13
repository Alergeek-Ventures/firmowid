defmodule FirmowidWeb.Auth.Controllers.AuthControllerTest do
  @moduledoc """
  Covers authentication session topics and revocation disconnects through HTTP.
  """

  use FirmowidWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias AshAuthentication.TokenResource
  alias Firmowid.Core
  alias Firmowid.Core.Token
  alias Phoenix.Socket.Broadcast

  test "reset and confirmation URLs never expose bearer credentials in request logs" do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
    credential = "sensitive-auth-credential-probe"

    for path <- ["resetuj-haslo", "potwierdz-email", "%72esetuj-haslo", "%70otwierdz-email"] do
      logs = capture_log([level: :info], fn -> get(build_conn(), "/#{path}/#{credential}") end)
      refute logs =~ credential
    end

    assert capture_log([level: :info], fn -> get(build_conn(), "/zaloguj") end) =~ "GET /zaloguj"
  end

  test "logout revokes the session token and broadcasts its exact topic", %{conn: conn} do
    user = user_fixture()
    user = Ash.Seed.update!(user, %{confirmed_at: DateTime.utc_now()})
    {:ok, lv, _html} = live(conn, ~p"/zaloguj")

    conn =
      lv
      |> form("#login_form",
        user: %{email: user.email, password: valid_user_password(), remember_me: false}
      )
      |> submit_form(conn)

    assert redirected_to(conn) == "/czasosledz"
    token = get_session(conn, :user_token)
    {:ok, %{"jti" => jti}} = Jwt.peek(token)
    topic = "users_sessions:#{jti}"
    assert get_session(conn, :live_socket_id) == topic
    Phoenix.PubSub.subscribe(Firmowid.PubSub, topic)

    conn = delete(conn, "/wyloguj")

    assert redirected_to(conn) == "/"
    assert TokenResource.token_revoked?(Token, token)
    assert_receive %Broadcast{topic: ^topic, event: "disconnect"}
  end

  test "logout during impersonation revokes both sessions and prevents returning", %{conn: conn} do
    superuser = Ash.Seed.update!(admin_fixture(), %{system_role: :superuser})
    owner = admin_fixture()

    impersonated =
      conn
      |> init_test_session(%{})
      |> Helpers.store_in_session(superuser)
      |> post("/admin/rozliczenia/#{owner.member.organization_id}/impersonacja")

    assert redirected_to(impersonated) == "/fakturowanie"
    superuser_token = get_session(impersonated, "impersonator_token")
    owner_token = get_session(impersonated, :user_token)

    logged_out = delete(impersonated, "/wyloguj")

    assert redirected_to(logged_out) == "/"
    assert TokenResource.token_revoked?(Token, owner_token)
    assert TokenResource.token_revoked?(Token, superuser_token)
    assert impersonated |> delete("/admin/impersonacja") |> redirected_to() == "/zaloguj"
  end

  test "independent token revocation broadcasts the token topic" do
    user = user_fixture()
    {:ok, token, %{"jti" => jti}} = Jwt.token_for_user(user)
    topic = "users_sessions:#{jti}"
    Phoenix.PubSub.subscribe(Firmowid.PubSub, topic)

    assert :ok = TokenResource.revoke(Token, token, store_all_tokens?: true)
    assert TokenResource.token_revoked?(Token, token)
    assert_receive %Broadcast{topic: ^topic, event: "disconnect"}
  end

  test "browser request restores the socket topic for a legacy session", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> init_test_session(%{})
      |> Helpers.store_in_session(user)
      |> get("/")

    {:ok, %{"jti" => jti}} = Jwt.peek(get_session(conn, :user_token))
    assert get_session(conn, :live_socket_id) == "users_sessions:#{jti}"
  end

  test "archiving keeps browser sessions, disconnects their LiveViews and sends them to onboarding",
       %{
         conn: conn
       } do
    admin = admin_fixture()
    user = user_in_org_fixture(admin.member.organization_id)

    connections =
      for _ <- 1..2 do
        session = conn |> init_test_session(%{}) |> Helpers.store_in_session(user)
        token = get_session(session, :user_token)
        {:ok, %{"jti" => jti}} = Jwt.peek(token)
        topic = "users_sessions:#{jti}"
        Phoenix.PubSub.subscribe(Firmowid.PubSub, topic)
        {session, token, topic}
      end

    archived =
      Core.archive_member!(user.member, actor: admin, tenant: admin.member.organization_id)

    for {session, token, topic} <- connections do
      refute TokenResource.token_revoked?(Token, token)
      assert_receive %Broadcast{topic: ^topic, event: "disconnect"}
      assert session |> get("/czasosledz") |> redirected_to() == "/organizacja"
    end

    Core.unarchive_member!(archived, actor: admin, tenant: admin.member.organization_id)

    for {session, _token, _topic} <- connections do
      assert session |> get("/czasosledz") |> html_response(200)
    end
  end

  describe "remember me" do
    setup do
      %{user: Ash.Seed.update!(user_fixture(), %{confirmed_at: DateTime.utc_now()})}
    end

    test "a ticked box signs the browser in again once the session is gone", %{
      conn: conn,
      user: user
    } do
      conn = sign_in(conn, user, true)

      assert %{value: token, http_only: true, same_site: "Lax", max_age: max_age} =
               conn.resp_cookies["remember_me"]

      assert max_age == 30 * 24 * 60 * 60

      assert {:ok, _lv, _html} =
               build_conn() |> put_req_cookie("remember_me", token) |> live(~p"/czasosledz")
    end

    test "an unticked box sets no cookie", %{conn: conn, user: user} do
      conn = sign_in(conn, user, false)

      assert redirected_to(conn) == "/czasosledz"
      refute Map.has_key?(conn.resp_cookies, "remember_me")
    end

    for {method, path} <- [delete: "/wyloguj", post: "/zaloguj-ponownie"] do
      test "#{method} #{path} deletes and revokes the cookie", %{conn: conn, user: user} do
        conn = sign_in(conn, user, true)
        token = conn.resp_cookies["remember_me"].value

        conn = conn |> recycle() |> unquote(method)(unquote(path))

        assert %{max_age: 0} = conn.resp_cookies["remember_me"]
        assert TokenResource.token_revoked?(Token, token)

        assert {:error, {:redirect, %{to: "/zaloguj"}}} =
                 build_conn() |> put_req_cookie("remember_me", token) |> live(~p"/czasosledz")
      end
    end
  end

  defp sign_in(conn, user, remember_me) do
    {:ok, lv, _html} = live(conn, ~p"/zaloguj")

    lv
    |> form("#login_form",
      user: %{email: user.email, password: valid_user_password(), remember_me: remember_me}
    )
    |> submit_form(conn)
  end
end
