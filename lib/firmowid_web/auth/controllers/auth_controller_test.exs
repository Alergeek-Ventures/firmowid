defmodule FirmowidWeb.Auth.Controllers.AuthControllerTest do
  @moduledoc """
  Covers authentication session topics and revocation disconnects through HTTP.
  """

  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias AshAuthentication.TokenResource
  alias Firmowid.Ash.Core.Token
  alias Phoenix.Socket.Broadcast

  test "logout revokes the session token and broadcasts its exact topic", %{conn: conn} do
    user = user_fixture()
    user = Ash.Seed.update!(user, %{confirmed_at: DateTime.utc_now()})
    {:ok, lv, _html} = live(conn, ~p"/zaloguj")

    conn =
      lv
      |> form("#login_form",
        user: %{email: user.email, password: valid_user_password()},
        remember_me: false
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
end
