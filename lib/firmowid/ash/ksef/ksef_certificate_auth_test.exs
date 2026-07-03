defmodule Firmowid.Ash.Ksef.CertificateAuthTest do
  @moduledoc false

  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Ash.Ksef.KsefTestHelpers, only: [jwt: 1]

  alias Firmowid.Ash.Core
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
               Ksef.authenticate_with_uploaded_certificate(
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

    assert {:ok, _access_token} = Cachex.get(:ksef, {:access_token, admin.organization_id})
  end

  test "session worker re-authenticates using stored certificate credentials", %{
    admin: admin,
    scope: scope,
    credentials: credentials
  } do
    assert {:ok, _credential} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Ksef.authenticate_with_uploaded_certificate(
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
             Ksef.authenticate_with_uploaded_certificate(
               credentials.certificate,
               credentials.private_key,
               "incorrect",
               scope
             )

    assert Ksef.get_credential(scope) == nil
  end

  test "removes credentials when session establishment raises", %{
    scope: scope,
    credentials: credentials
  } do
    Req.Test.stub(:ksef_domain_certificate_api, fn
      %{request_path: "/auth/token/redeem"} = conn ->
        Req.Test.json(conn, %{
          "accessToken" => %{"token" => "invalid-access-token"},
          "refreshToken" => %{"token" => jwt(7 * 86_400)}
        })

      conn ->
        successful_ksef_response(conn)
    end)

    assert_raise FunctionClauseError, fn ->
      Oban.Testing.with_testing_mode(:manual, fn ->
        Ksef.authenticate_with_uploaded_certificate(
          credentials.certificate,
          credentials.private_key,
          credentials.password,
          scope
        )
      end)
    end

    assert Ksef.get_credential(scope) == nil
  end

  test "validates an externally signed request before enqueueing it", %{
    admin: admin,
    scope: scope
  } do
    organization = Core.get_organization!(admin.organization_id, scope: scope)
    signed_xml = signed_auth_token_request("expected-challenge", organization.nip)

    assert {:error, :auth_token_request_mismatch} =
             Ksef.enroll_ksef_certificate(signed_xml, "different-challenge", scope)

    assert {:error, :auth_token_request_mismatch} =
             Ksef.enroll_ksef_certificate(signed_xml, nil, scope)

    assert {:error, :invalid_xml} =
             Ksef.enroll_ksef_certificate("<AuthTokenRequest>", "expected-challenge", scope)

    assert {:error, :unsafe_xml} =
             Ksef.enroll_ksef_certificate(
               "<!DOCTYPE AuthTokenRequest [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]>#{signed_xml}",
               "expected-challenge",
               scope
             )

    assert {:ok, job} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Ksef.enroll_ksef_certificate(signed_xml, "expected-challenge", scope)
             end)

    assert job.args["action"] == "authenticate"
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

  defp signed_auth_token_request(challenge, nip) do
    """
    <AuthTokenRequest xmlns="http://ksef.mf.gov.pl/auth/token/2.0"
                      xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
      <Challenge>#{challenge}</Challenge>
      <ContextIdentifier><Nip>#{nip}</Nip></ContextIdentifier>
      <SubjectIdentifierType>certificateSubject</SubjectIdentifierType>
      <ds:Signature><ds:SignedInfo /></ds:Signature>
    </AuthTokenRequest>
    """
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

  defp raw_credentials(organization_id) do
    %{rows: [[credentials]]} =
      Repo.query!(
        "SELECT credentials FROM ksef_credentials WHERE organization_id::text = $1",
        [organization_id]
      )

    credentials
  end
end
