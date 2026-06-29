defmodule Firmowid.Ash.Ksef.Services.ApiClientCertificateTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Firmowid.Ash.Ksef.Services.ApiClient

  @context_nip "6161525811"

  setup_all do
    private_key = X509.PrivateKey.new_ec(:secp256r1)
    certificate = X509.Certificate.self_signed(private_key, "/C=PL/O=Firmowid/CN=KSeF Test")

    %{
      certificate_pem: X509.Certificate.to_pem(certificate),
      private_key_pem: X509.PrivateKey.to_pem(private_key, wrap: true)
    }
  end

  setup do
    original_config = Application.fetch_env!(:firmowid, :ksef)

    Application.put_env(
      :firmowid,
      :ksef,
      Keyword.merge(original_config,
        base_url: "https://ksef.example",
        auth_status_max_attempts: 3,
        auth_status_poll_interval_ms: 0,
        request_options: [plug: {Req.Test, :ksef_certificate_api}]
      )
    )

    on_exit(fn ->
      Application.put_env(:firmowid, :ksef, original_config)
    end)

    :ok
  end

  test "runs the complete certificate authentication flow", credentials do
    {:ok, status_counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(:ksef_certificate_api, fn conn ->
      handle_successful_request(conn, status_counter)
    end)

    assert {:ok,
            %{
              access_token: "access-token",
              refresh_token: "refresh-token"
            }} =
             ApiClient.auth_with_ksef_certificate(
               @context_nip,
               credentials.certificate_pem,
               credentials.private_key_pem,
               nil
             )

    assert Agent.get(status_counter, & &1) == 2
  end

  test "returns a timeout when KSeF never completes authentication", credentials do
    config = Application.fetch_env!(:firmowid, :ksef)
    Application.put_env(:firmowid, :ksef, Keyword.put(config, :auth_status_max_attempts, 2))

    Req.Test.stub(:ksef_certificate_api, fn conn ->
      case conn.request_path do
        "/auth/challenge" ->
          Req.Test.json(conn, %{"challenge" => "challenge", "timestamp" => "2026-01-01T00:00:00Z"})

        "/auth/xades-signature" ->
          conn
          |> Plug.Conn.put_status(202)
          |> Req.Test.json(%{
            "referenceNumber" => "timeout-ref",
            "authenticationToken" => %{"token" => "temporary-token"}
          })

        "/auth/timeout-ref" ->
          Req.Test.json(conn, %{"status" => %{"code" => 100}})

        path ->
          Plug.Conn.send_resp(conn, 404, "unexpected request: #{path}")
      end
    end)

    assert {:error, :auth_status_timeout} =
             ApiClient.auth_with_ksef_certificate(
               @context_nip,
               credentials.certificate_pem,
               credentials.private_key_pem,
               nil
             )
  end

  test "rejects invalid NIP context before making a request", credentials do
    assert {:error, :invalid_context_nip} =
             ApiClient.auth_with_ksef_certificate(
               "PL-6161525811",
               credentials.certificate_pem,
               credentials.private_key_pem,
               nil
             )
  end

  defp handle_successful_request(conn, status_counter) do
    case conn.request_path do
      "/auth/challenge" ->
        assert conn.method == "POST"
        Req.Test.json(conn, %{"challenge" => "challenge", "timestamp" => "2026-01-01T00:00:00Z"})

      "/auth/xades-signature" ->
        assert conn.method == "POST"
        assert conn.query_string == "verifyCertificateChain=false"
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/xml"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "<AuthTokenRequest "
        assert body =~ "<ds:Signature "
        assert body =~ "ecdsa-sha256"

        conn
        |> Plug.Conn.put_status(202)
        |> Req.Test.json(%{
          "referenceNumber" => "authentication-ref",
          "authenticationToken" => %{"token" => "temporary-token"}
        })

      "/auth/authentication-ref" ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer temporary-token"]

        status = Agent.get_and_update(status_counter, fn count -> {count, count + 1} end)
        code = if status == 0, do: 100, else: 200
        Req.Test.json(conn, %{"status" => %{"code" => code}})

      "/auth/token/redeem" ->
        assert conn.method == "POST"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer temporary-token"]

        Req.Test.json(conn, %{
          "accessToken" => %{"token" => "access-token"},
          "refreshToken" => %{"token" => "refresh-token"}
        })

      path ->
        Plug.Conn.send_resp(conn, 404, "unexpected request: #{path}")
    end
  end
end
