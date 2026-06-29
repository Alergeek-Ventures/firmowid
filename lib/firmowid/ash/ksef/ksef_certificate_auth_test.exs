defmodule Firmowid.Ash.Ksef.CertificateAuthTest do
  @moduledoc false

  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Workers.SessionWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Repo

  setup do
    admin = admin_fixture()
    scope = %Scope{actor: admin, tenant: admin.organization_id}
    credentials = certificate_credentials()
    original_config = Application.fetch_env!(:firmowid, :ksef)

    Application.put_env(
      :firmowid,
      :ksef,
      Keyword.merge(original_config,
        base_url: "https://ksef.example",
        auth_status_max_attempts: 2,
        auth_status_poll_interval_ms: 0,
        request_options: [plug: {Req.Test, :ksef_domain_certificate_api}]
      )
    )

    Cachex.put(
      :ksef,
      {:public_key, "SymmetricKeyEncryption"},
      credentials.ksef_public_key
    )

    Req.Test.stub(:ksef_domain_certificate_api, &successful_ksef_response/1)

    on_exit(fn ->
      Application.put_env(:firmowid, :ksef, original_config)
      Cachex.del(:ksef, {:access_token, admin.organization_id})
      Cachex.del(:ksef, {:public_key, "SymmetricKeyEncryption"})
    end)

    %{admin: admin, scope: scope, credentials: credentials}
  end

  test "persists encrypted certificate credentials only after successful authentication", %{
    admin: admin,
    scope: scope,
    credentials: credentials
  } do
    assert Ksef.get_credential(scope) == nil

    assert {:ok, credential} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Ksef.authenticate_with_ksef_certificate(
                 credentials.certificate,
                 credentials.private_key,
                 credentials.password,
                 scope
               )
             end)

    assert credential.auth_type == :certificate

    assert {:ok,
            %{
              "certificate" => certificate,
              "private_key" => private_key,
              "private_key_password" => password
            }} = Jason.decode(credential.credentials)

    assert certificate == credentials.certificate
    assert private_key == credentials.private_key
    assert password == credentials.password

    raw_credentials = raw_credentials(admin.organization_id)
    refute raw_credentials =~ credentials.certificate
    refute raw_credentials =~ credentials.private_key
    refute raw_credentials =~ credentials.password

    assert {:ok, access_token} = Cachex.get(:ksef, {:access_token, admin.organization_id})
  end

  test "session worker re-authenticates using stored certificate credentials", %{
    admin: admin,
    scope: scope,
    credentials: credentials
  } do
    assert {:ok, _credential} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Ksef.authenticate_with_ksef_certificate(
                 credentials.certificate,
                 credentials.private_key,
                 credentials.password,
                 scope
               )
             end)

    Cachex.del(:ksef, {:access_token, admin.organization_id})

    assert {:ok, true} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               perform_job(SessionWorker, %{"organization_id" => admin.organization_id})
             end)

    assert {:ok, access_token} = Cachex.get(:ksef, {:access_token, admin.organization_id})
    assert access_token == jwt(3_600)
  end

  test "does not persist credentials when the private key password is wrong", %{
    scope: scope,
    credentials: credentials
  } do
    assert {:error, :invalid_private_key} =
             Ksef.authenticate_with_ksef_certificate(
               credentials.certificate,
               credentials.private_key,
               "incorrect",
               scope
             )

    assert Ksef.get_credential(scope) == nil
  end

  defp certificate_credentials do
    password = "certificate-password"
    private_key = X509.PrivateKey.new_ec(:secp256r1)
    certificate = X509.Certificate.self_signed(private_key, "/C=PL/O=Firmowid/CN=KSeF Test")
    ksef_public_key = X509.PrivateKey.new_rsa(2048)
    ksef_public_certificate = X509.Certificate.self_signed(ksef_public_key, "/CN=KSeF Encryption")

    path = Briefly.create!(extname: ".pem")
    File.write!(path, X509.PrivateKey.to_pem(private_key, wrap: true))

    {encrypted_private_key, 0} =
      System.cmd(
        "openssl",
        [
          "pkcs8",
          "-topk8",
          "-v2",
          "aes-256-cbc",
          "-in",
          path,
          "-passout",
          "pass:#{password}"
        ],
        stderr_to_stdout: true
      )

    %{
      certificate: X509.Certificate.to_pem(certificate),
      private_key: encrypted_private_key,
      password: password,
      ksef_public_key: ksef_public_certificate
    }
  end

  defp successful_ksef_response(conn) do
    case conn.request_path do
      "/auth/challenge" ->
        Req.Test.json(conn, %{"challenge" => "challenge", "timestamp" => "2026-01-01T00:00:00Z"})

      "/auth/xades-signature" ->
        conn
        |> Plug.Conn.put_status(202)
        |> Req.Test.json(%{
          "referenceNumber" => "authentication-ref",
          "authenticationToken" => %{"token" => "temporary-token"}
        })

      "/auth/authentication-ref" ->
        Req.Test.json(conn, %{"status" => %{"code" => 200}})

      "/auth/token/redeem" ->
        Req.Test.json(conn, %{
          "accessToken" => %{"token" => jwt(3_600)},
          "refreshToken" => %{"token" => jwt(7 * 86_400)}
        })

      "/invoices/exports" ->
        Req.Test.json(conn, %{"error" => "fetch intentionally disabled in authentication test"})

      path ->
        Plug.Conn.send_resp(conn, 404, "unexpected request: #{path}")
    end
  end

  defp jwt(seconds_from_now) do
    header = Base.url_encode64(Jason.encode!(%{"alg" => "none"}), padding: false)

    payload =
      Base.url_encode64(Jason.encode!(%{"exp" => System.os_time(:second) + seconds_from_now}),
        padding: false
      )

    "#{header}.#{payload}.signature"
  end

  defp raw_credentials(organization_id) do
    %{rows: [[credentials]]} =
      Repo.query!(
        "SELECT credentials FROM ksef_credentials WHERE organization_id::text = $1",
        [organization_id]
      )

    credentials
  end
end
