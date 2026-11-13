defmodule FirmowidWeb.Auth.Utilities.PendingAuthorizationTest do
  @moduledoc """
  Connecting an AI client from a new account: signing up, setting up the company
  in the web app and returning to the consent, with and without the setup wizard.
  """

  # The setup wizard is behind the inbox flag. Flags are application config in
  # tests, so this module runs alone.
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias AshAuthentication.Oauth2Server.PKCE
  alias AshAuthentication.Oauth2Server.Register
  alias Firmowid.Core
  alias Firmowid.Oauth2Server

  @redirect_uri "https://chatgpt.example/connector/oauth/callback"

  setup do
    on_exit(fn -> Application.delete_env(:firmowid, :enabled_feature_flags) end)

    {:ok, client, _response} =
      Register.register(Oauth2Server, %{
        "client_name" => "ChatGPT",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    %{
      client: client,
      verifier: verifier,
      authorize_path: authorize_path(client, verifier),
      email: unique_user_email()
    }
  end

  test "a new account creates its company and returns to the consent, without the setup wizard",
       %{authorize_path: authorize_path} = context do
    conn = sign_up(context)

    # Without a company the consent waits; the organization form says why.
    conn = get(recycle(conn), authorize_path)
    assert redirected_to(conn) == ~p"/organizacja"

    assert {:error, {:live_redirect, %{to: "/organizacja/formularz"}}} =
             live(recycle(conn), ~p"/organizacja")

    {:ok, _form, html} = live(recycle(conn), ~p"/organizacja/formularz")
    assert html =~ "ChatGPT"

    user = Core.load_member(Core.get_user_by_email!(context.email, authorize?: false))

    organization =
      Core.create_organization!(
        %{nip: unique_nip(), name: "Acme Sp. z o.o.", owner_name: "Jan Kowalski"},
        actor: user
      )

    conn = post(recycle(conn), ~p"/organizacja/przelacz", %{"organizacja" => organization.id})
    assert redirected_to(conn) == authorize_path

    token = approve_and_exchange(recycle(conn), context, organization.id)
    assert_no_ksef_setup_in_mcp(token)
  end

  test "a new account sets up its company in the wizard and returns to the consent",
       %{authorize_path: authorize_path} = context do
    Application.put_env(:firmowid, :enabled_feature_flags, [:inbox])
    Req.Test.stub(:nip_api, &Req.Test.json(&1, %{"result" => %{"subject" => nil}}))

    conn = sign_up(context)
    conn = get(recycle(conn), authorize_path)
    assert redirected_to(conn) == ~p"/organizacja"

    {:ok, wizard, _html} = live(recycle(conn), ~p"/organizacja?krok=firma")
    # The progress says where the setup ends.
    assert has_element?(wizard, "header", "ChatGPT")

    # The VAT white list does not know the NIP, so the owner enters the details.
    wizard |> form("#company-form", %{"nip" => "5261040828"}) |> render_change()
    render_async(wizard)

    wizard
    |> form("#company-form", %{
      "nip" => "5261040828",
      "name" => "Acme Sp. z o.o.",
      "address" => "Prosta 1, 00-001 Warszawa",
      "owner_name" => "Jan Kowalski"
    })
    |> render_submit()

    wizard
    |> form("#industry-form", %{"industry" => "services", "bills_hourly" => "false"})
    |> render_submit()

    conn = wizard |> form("#switch-organization-form") |> follow_trigger_action(recycle(conn))
    assert redirected_to(conn) == ~p"/pierwsze-kroki"

    # The consent waits for the first steps, KSeF among them, which take place here, in the web app.
    assert redirected_to(get(recycle(conn), authorize_path)) == ~p"/organizacja?krok=firma"

    {:ok, first_steps, _html} = live(recycle(conn), ~p"/pierwsze-kroki?krok=gotowe")
    assert has_element?(first_steps, "#go-to-app", "ChatGPT")

    assert {:error, {:redirect, %{to: ^authorize_path}}} =
             first_steps |> form("#finish-form") |> render_submit()

    organization_id =
      Core.load_member(Core.get_user_by_email!(context.email, authorize?: false)).member.organization_id

    token = approve_and_exchange(recycle(conn), context, organization_id)
    assert_no_ksef_setup_in_mcp(token)
  end

  test "a long client name stays off the sign-in page" do
    {:ok, client, _response} =
      Register.register(Oauth2Server, %{
        "client_name" => "ChatGPT. Your account is blocked, call the number below right now",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    conn =
      get(build_conn(), authorize_path(client, "verifier-verifier-verifier-verifier-verifier"))

    {:ok, _login, html} = live(recycle(conn), ~p"/zaloguj")

    refute html =~ "Your account is blocked"
  end

  test "a request too long for the session still leads to the setup, without promising a return",
       %{client: client} do
    conn =
      log_in_user(
        build_conn(),
        Core.register_with_password!(
          %{email: unique_user_email(), password: valid_user_password()},
          authorize?: false,
          actor: %{}
        )
      )

    long_path =
      authorize_path(client, "verifier-verifier-verifier-verifier-verifier") <>
        "&state=" <> String.duplicate("s", 2000)

    conn = get(conn, long_path)
    assert redirected_to(conn) == ~p"/organizacja"

    {:ok, _form, html} = live(recycle(conn), ~p"/organizacja/formularz")
    refute html =~ "ChatGPT"
  end

  # Signs up from the sign-in page the OAuth server leads to, which names the client.
  defp sign_up(context) do
    conn = get(build_conn(), context.authorize_path)
    assert redirected_to(conn) =~ ~p"/zaloguj"

    {:ok, _login, login_html} = live(recycle(conn), ~p"/zaloguj")
    assert login_html =~ "ChatGPT"

    {:ok, registration, registration_html} = live(recycle(conn), ~p"/zarejestruj")
    assert registration_html =~ "ChatGPT"

    form =
      form(registration, "#registration_form", user: valid_user_attributes(email: context.email))

    render_submit(form)
    conn = follow_trigger_action(form, recycle(conn))

    assert redirected_to(conn) == context.authorize_path
    conn
  end

  defp approve_and_exchange(conn, context, organization_id) do
    conn = get(conn, context.authorize_path)
    html = html_response(conn, 200)
    # The consent form names the one company the new account has.
    assert html =~ ~s(name="organization_id" value="#{organization_id}")
    [_, consent_request] = Regex.run(~r/name="consent_request" value="([^"]+)"/, html)

    conn =
      post(recycle(conn), "/oauth/authorize", %{
        "consent_request" => consent_request,
        "action" => "approve",
        "organization_id" => organization_id
      })

    location = redirected_to(conn, 302)
    assert String.starts_with?(location, @redirect_uri)
    %{"code" => code} = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    %{"access_token" => token} =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => code,
        "client_id" => context.client.id,
        "code_verifier" => context.verifier
      })
      |> json_response(200)

    token
  end

  # The connected client gets no tool or view for KSeF credentials, and the server sends it to the web app.
  defp assert_no_ksef_setup_in_mcp(token) do
    %{"instructions" => instructions} =
      mcp(token, "initialize", %{
        "protocolVersion" => "2025-03-26",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "pending-authorization", "version" => "1"}
      })

    assert instructions =~ FirmowidMcp.Ksef.settings_url()
    refute instructions =~ ~r/widget[^.]*(token|password|private key|certificate)/i

    # Listing tools and resources renders the widget document from built assets, which tests
    # lack, so the allowlists the router serves are checked instead.
    assert Enum.filter(Firmowid.AiTools.mcp(), &(to_string(&1) =~ "ksef")) == [
             :get_ksef_connection_status
           ]

    refute Enum.any?(FirmowidMcp.Widgets.all(), &(&1.resource_uri() =~ "ksef"))

    # The new company has no KSeF yet; the status itself carries the way to connect it.
    assert %{"status" => "disconnected", "settings_url" => settings_url} =
             mcp(token, "tools/call", %{
               "name" => "get_ksef_connection_status",
               "arguments" => %{}
             })[
               "structuredContent"
             ]

    assert settings_url == FirmowidMcp.Ksef.settings_url()
  end

  defp mcp(token, method, params) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> put_req_header("content-type", "application/json")
    |> post(
      "/mcp",
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})
    )
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp authorize_path(client, verifier) do
    "/oauth/authorize?" <>
      URI.encode_query(%{
        "client_id" => client.id,
        "response_type" => "code",
        "redirect_uri" => @redirect_uri,
        "code_challenge" => PKCE.challenge(verifier),
        "code_challenge_method" => "S256",
        "scope" => "mcp"
      })
  end
end
