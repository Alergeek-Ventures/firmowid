defmodule FirmowidWeb.Auth.Utilities.GoogleRememberMeTest do
  @moduledoc """
  Signs in with Google through the real strategy, against a stand-in for Google's
  endpoints, with and without "Remember me".
  """

  # Swaps the application's Google credentials and HTTP adapter.
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias Assent.HTTPAdapter.HTTPResponse
  alias Firmowid.Core

  defmodule FakeGoogle do
    @moduledoc """
    Answers the strategy's requests to Google. The authorization step happens in
    the browser, so the test hands the request's nonce back as the code, and the
    ID token carries it.
    """
    @behaviour Assent.HTTPAdapter

    @issuer "https://accounts.google.com"
    @token_endpoint "https://oauth2.googleapis.com/token"
    @jwks_uri "https://www.googleapis.com/oauth2/v3/certs"

    @impl true
    def request(:get, @issuer <> "/.well-known/openid-configuration", _body, _headers, _opts) do
      json(%{
        "issuer" => @issuer,
        "authorization_endpoint" => @issuer <> "/o/oauth2/v2/auth",
        "token_endpoint" => @token_endpoint,
        "jwks_uri" => @jwks_uri,
        "id_token_signing_alg_values_supported" => ["RS256"],
        "token_endpoint_auth_methods_supported" => ["client_secret_post"]
      })
    end

    def request(:get, @jwks_uri, _body, _headers, opts) do
      {_fields, key} = opts |> Keyword.fetch!(:key) |> JOSE.JWK.to_public_map()
      json(%{"keys" => [Map.merge(key, %{"kid" => "test", "alg" => "RS256", "use" => "sig"})]})
    end

    def request(:post, @token_endpoint, body, _headers, opts) do
      %{"code" => nonce} = URI.decode_query(body)
      now = System.system_time(:second)

      claims = %{
        "iss" => @issuer,
        "aud" => "test-client-id",
        "sub" => "google-#{opts[:email]}",
        "iat" => now,
        "exp" => now + 300,
        "nonce" => nonce,
        "email" => opts[:email],
        "email_verified" => true
      }

      {_fields, id_token} =
        opts
        |> Keyword.fetch!(:key)
        |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "test"}, claims)
        |> JOSE.JWS.compact()

      json(%{
        "access_token" => "test-access-token",
        "token_type" => "Bearer",
        "id_token" => id_token
      })
    end

    defp json(body) do
      {:ok,
       %HTTPResponse{
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(body)
       }}
    end
  end

  setup_all do
    %{key: JOSE.JWK.generate_key({:rsa, 2048})}
  end

  setup %{key: key} do
    user = Ash.Seed.update!(user_fixture(), %{confirmed_at: DateTime.utc_now()})

    put_env(:firmowid, :google_client_id, "test-client-id")
    put_env(:firmowid, :google_client_secret, "test-client-secret")

    put_env(
      :ash_authentication,
      :http_adapter,
      {FakeGoogle, key: key, email: to_string(user.email)}
    )

    %{user: user}
  end

  test "a ticked box remembers the browser, and the sign-in still counts as fresh", %{conn: conn} do
    conn = google_sign_in(conn, "?remember_me=true")

    assert redirected_to(conn) == "/czasosledz"

    assert %{value: token, http_only: true, same_site: "Lax", max_age: max_age} =
             conn.resp_cookies["remember_me"]

    assert max_age == 30 * 24 * 60 * 60
    {:ok, claims} = conn |> get_session(:user_token) |> Jwt.peek()
    refute Map.has_key?(claims, "remembered")
    refute get_session(conn, "google_remember_me")

    assert {:ok, _lv, _html} =
             build_conn() |> put_req_cookie("remember_me", token) |> live(~p"/czasosledz")
  end

  test "an unticked box sets no cookie, even after an abandoned ticked attempt", %{conn: conn} do
    conn = get(conn, ~p"/auth/user/google?remember_me=true")
    conn = conn |> recycle() |> google_sign_in("")

    assert redirected_to(conn) == "/czasosledz"
    refute Map.has_key?(conn.resp_cookies, "remember_me")
  end

  test "a failed callback drops the choice from the session", %{conn: conn} do
    conn = get(conn, ~p"/auth/user/google?remember_me=true")
    assert get_session(conn, "google_remember_me")

    conn = conn |> recycle() |> get(~p"/auth/user/google/callback", code: "x", state: "forged")

    assert redirected_to(conn) == "/zaloguj"
    refute get_session(conn, "google_remember_me")
    refute Map.has_key?(conn.resp_cookies, "remember_me")
  end

  test "a blocked account is not remembered", %{conn: conn, key: key} do
    admin = Ash.Seed.update!(admin_fixture(), %{confirmed_at: DateTime.utc_now()})
    organization = Core.get_organization!(admin.member.organization_id, authorize?: false)

    Core.update_organization_billing_plan!(organization, %{billing_plan: :no_plan}, authorize?: false)

    put_env(
      :ash_authentication,
      :http_adapter,
      {FakeGoogle, key: key, email: to_string(admin.email)}
    )

    conn = google_sign_in(conn, "?remember_me=true")

    assert redirected_to(conn) =~ ~p"/abonament-wygasl"
    assert %{max_age: 0} = conn.resp_cookies["remember_me"]
  end

  # Starts the sign-in from the Google button's link, then returns from Google with
  # the request's state, and its nonce as the code (see `FakeGoogle`).
  defp google_sign_in(conn, query) do
    conn = get(conn, "/auth/user/google" <> query)

    %{"state" => state, "nonce" => nonce} =
      conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    conn |> recycle() |> get(~p"/auth/user/google/callback", code: nonce, state: state)
  end

  defp put_env(app, key, value) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(app, key, value)
        :error -> Application.delete_env(app, key)
      end
    end)
  end
end
