defmodule Firmowid.Ksef.Workers.CertificateEnrollmentWorkerTest do
  @moduledoc false

  use Firmowid.DataCase, async: false

  import Ecto.Query
  import Firmowid.AccountsFixtures
  import Firmowid.Ksef.KsefTestHelpers, only: [jwt: 1]

  alias Firmowid.Ksef
  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.CredentialMetadata
  alias Firmowid.Ksef.Workers.CertificateEnrollmentWorker
  alias Firmowid.Repo
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @moduletag capture_log: true

  setup do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    original_config = Application.fetch_env!(:firmowid, :ksef)

    Application.put_env(
      :firmowid,
      :ksef,
      Keyword.merge(original_config,
        base_url: "https://ksef.example",
        request_options: [plug: {Req.Test, :ksef_certificate_refresh_api}]
      )
    )

    Cachex.put(:ksef, {:access_token, organization_id}, jwt(3_600))

    on_exit(fn ->
      Application.put_env(:firmowid, :ksef, original_config)
      Cachex.del(:ksef, {:access_token, organization_id})
    end)

    %{organization_id: organization_id, scope: ksef_scope(organization_id), admin: admin}
  end

  for auth_type <- [:generated_certificate, :certificate] do
    @tag auth_type: auth_type
    test "replaces a #{auth_type}, revoking only Firmowid-generated certificates", %{
      organization_id: organization_id,
      scope: scope,
      auth_type: auth_type
    } do
      {certificate, private_key} = certificate_material("Current certificate")
      {successor, _key} = certificate_material("Successor")
      credential = seed_working_credential(organization_id, certificate, private_key, auth_type)
      serial = CredentialMetadata.certificate_serial_number(credential)

      Req.Test.stub(:ksef_certificate_refresh_api, fn conn ->
        if auth_type == :certificate, do: refute(String.ends_with?(conn.request_path, "/revoke"))
        successful_refresh_response(conn, successor, serial)
      end)

      Oban.Testing.with_testing_mode(:manual, fn ->
        refreshing = Credential.refresh_certificate!(credential, scope: scope)
        assert %{success: 1} = Oban.drain_queue(queue: :ksef_sessions)
        poll_args = queued_poll_args(organization_id)
        assert poll_args["credential_id"] == credential.id
        assert poll_args["refresh_started_at"] == DateTime.to_iso8601(refreshing.updated_at)
        assert :ok = perform_job(CertificateEnrollmentWorker, poll_args)
      end)

      refreshed = Credential.get_internal!(scope: scope)
      assert refreshed.status == :working
      assert refreshed.auth_type == :generated_certificate

      assert %{"certificate" => refreshed_certificate, "private_key" => refreshed_private_key} =
               Jason.decode!(refreshed.credentials)

      assert String.trim_trailing(refreshed_certificate) == String.trim_trailing(successor)
      assert refreshed_private_key != private_key
      assert refreshed.expires_on == certificate_expiration_date(successor)
    end
  end

  test "cancels stale refresh jobs after credentials are removed", %{
    organization_id: organization_id
  } do
    assert {:cancel, :no_credentials} =
             perform_job(CertificateEnrollmentWorker, refresh_args(organization_id))
  end

  test "keeps the current certificate connected when renewal reaches KSeF limits", %{
    organization_id: organization_id,
    scope: scope
  } do
    {certificate, private_key} = certificate_material("Current certificate")

    credential =
      seed_working_credential(organization_id, certificate, private_key, :generated_certificate)

    Req.Test.stub(:ksef_certificate_refresh_api, fn conn ->
      Req.Test.json(conn, %{
        "canRequest" => false,
        "certificate" => %{"remaining" => 0},
        "enrollment" => %{"remaining" => 0}
      })
    end)

    assert {:ok, %Credential{status: :refreshing}} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Credential.refresh_certificate(credential, scope: scope)
             end)

    assert {:cancel, :certificate_limit_exhausted} =
             perform_job(CertificateEnrollmentWorker, refresh_args(organization_id), attempt: 5)

    assert %Credential{status: :working, credentials: credentials} =
             Credential.get_internal!(scope: scope)

    assert credentials == credential.credentials
  end

  test "disconnect cancels a retryable certificate poll", %{
    organization_id: organization_id,
    scope: scope,
    admin: admin
  } do
    {certificate, key} = certificate_material("Current certificate")
    seed_working_credential(organization_id, certificate, key, :generated_certificate)
    Req.Test.stub(:ksef_certificate_refresh_api, &Plug.Conn.send_resp(&1, 204, ""))

    Oban.Testing.with_testing_mode(:manual, fn ->
      poll =
        %{"action" => "poll_certificate_refresh", "organization_id" => organization_id}
        |> CertificateEnrollmentWorker.new(state: "retryable")
        |> Firmowid.Oban.insert!(skip_organization_id: true)

      assert {:ok, :disconnected} =
               Ksef.unauthenticate(%Scope{actor: admin, tenant: organization_id})

      assert Repo.get!(Oban.Job, poll.id, oban_jobs: true).state == "cancelled"
      assert Credential.get_internal!(scope: scope) == nil
    end)
  end

  test "cancels a poll from an earlier refresh before contacting KSeF", %{
    organization_id: organization_id,
    scope: scope
  } do
    {certificate, key} = certificate_material("Current certificate")

    credential =
      seed_working_credential(organization_id, certificate, key, :generated_certificate)

    Req.Test.stub(:ksef_certificate_refresh_api, fn _ -> flunk("stale poll reached KSeF") end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      refreshing = Credential.refresh_certificate!(credential, scope: scope)
      working = Credential.recover_certificate_refresh!(refreshing, scope: scope)
      Credential.refresh_certificate!(working, scope: scope)

      assert {:cancel, :stale_certificate_refresh} =
               perform_job(CertificateEnrollmentWorker, %{
                 "action" => "poll_certificate_refresh",
                 "organization_id" => organization_id,
                 "credential_id" => refreshing.id,
                 "refresh_started_at" => DateTime.to_iso8601(refreshing.updated_at)
               })

      current = Credential.get_internal!(scope: scope)
      assert current.credentials == credential.credentials
      assert current.status == :refreshing
    end)
  end

  test "restarts a poll without generation args and completes the current refresh", %{
    organization_id: organization_id,
    scope: scope
  } do
    {certificate, key} = certificate_material("Current certificate")
    {successor, _key} = certificate_material("Successor")

    credential =
      seed_working_credential(organization_id, certificate, key, :generated_certificate)

    serial = CredentialMetadata.certificate_serial_number(credential)

    Req.Test.stub(
      :ksef_certificate_refresh_api,
      &successful_refresh_response(&1, successor, serial)
    )

    Oban.Testing.with_testing_mode(:manual, fn ->
      Credential.refresh_certificate!(credential, scope: scope)
      assert %{success: 1} = Oban.drain_queue(queue: :ksef_sessions)
      args = Map.drop(queued_poll_args(organization_id), ["credential_id", "refresh_started_at"])

      assert {:cancel, :unbound_certificate_refresh_restarted} =
               perform_job(CertificateEnrollmentWorker, args)

      assert Credential.get_internal!(scope: scope).status == :refreshing

      [restart] =
        all_enqueued(worker: CertificateEnrollmentWorker, args: %{action: "refresh_certificate"})

      assert :ok = perform_job(CertificateEnrollmentWorker, restart.args)

      [new_poll | _] =
        all_enqueued(
          worker: CertificateEnrollmentWorker,
          args: %{action: "poll_certificate_refresh"}
        )

      assert :ok = perform_job(CertificateEnrollmentWorker, new_poll.args)
      assert Credential.get_internal!(scope: scope).status == :working
    end)
  end

  test "does not replace or revoke a certificate when its refresh changes during retrieval", %{
    organization_id: organization_id,
    scope: scope
  } do
    {certificate, key} = certificate_material("Current certificate")
    {successor, _key} = certificate_material("Successor")

    credential =
      seed_working_credential(organization_id, certificate, key, :generated_certificate)

    serial = CredentialMetadata.certificate_serial_number(credential)

    Req.Test.stub(:ksef_certificate_refresh_api, fn conn ->
      if conn.request_path == "/certificates/retrieve" do
        current = Credential.get_internal!(scope: scope)
        working = Credential.recover_certificate_refresh!(current, scope: scope)
        Credential.refresh_certificate!(working, scope: scope)
      end

      refute String.ends_with?(conn.request_path, "/revoke")
      successful_refresh_response(conn, successor, serial)
    end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      Credential.refresh_certificate!(credential, scope: scope)
      assert %{success: 1} = Oban.drain_queue(queue: :ksef_sessions)

      assert {:error, _stale_record} =
               perform_job(CertificateEnrollmentWorker, queued_poll_args(organization_id))

      current = Credential.get_internal!(scope: scope)
      assert current.credentials == credential.credentials
      assert current.status == :refreshing
    end)
  end

  defp ksef_scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :ksef_session},
      tenant: organization_id
    }
  end

  defp seed_working_credential(organization_id, certificate, private_key, auth_type) do
    Ash.Seed.seed!(Credential, %{
      organization_id: organization_id,
      status: :working,
      auth_type: auth_type,
      credentials: certificate_credentials(certificate, private_key),
      expires_on: Date.add(Date.utc_today(), 7)
    })
  end

  defp certificate_material(common_name) do
    private_key = X509.PrivateKey.new_ec(:secp256r1)
    certificate = X509.Certificate.self_signed(private_key, "/C=PL/O=Firmowid/CN=#{common_name}")

    {X509.Certificate.to_pem(certificate), X509.PrivateKey.to_pem(private_key, wrap: true)}
  end

  defp certificate_credentials(certificate, private_key) do
    Jason.encode!(%{
      "certificate" => certificate,
      "private_key" => private_key,
      "private_key_password" => nil
    })
  end

  defp refresh_args(organization_id) do
    %{"action" => "refresh_certificate", "organization_id" => organization_id}
  end

  defp queued_poll_args(organization_id) do
    query =
      from job in Oban.Job,
        where:
          job.worker == "Firmowid.Ksef.Workers.CertificateEnrollmentWorker" and
            fragment("?->>'action'", job.args) == "poll_certificate_refresh" and
            fragment("?->>'organization_id'", job.args) == ^organization_id,
        select: job.args

    Repo.one!(query, oban_jobs: true)
  end

  defp certificate_expiration_date(certificate) do
    {:Validity, _not_before, not_after} =
      certificate
      |> X509.Certificate.from_pem!()
      |> X509.Certificate.validity()

    not_after
    |> X509.DateTime.to_datetime()
    |> DateTime.to_date()
  end

  defp successful_refresh_response(conn, new_certificate, old_serial_number) do
    case conn.request_path do
      "/certificates/limits" ->
        Req.Test.json(conn, %{
          "canRequest" => true,
          "certificate" => %{"remaining" => 1},
          "enrollment" => %{"remaining" => 1}
        })

      "/certificates/enrollments/data" ->
        Req.Test.json(conn, certificate_subject_data())

      "/certificates/enrollments" ->
        assert %{
                 "certificateName" => "Firmowid-" <> _,
                 "certificateType" => "Authentication",
                 "csr" => csr
               } =
                 conn.body_params

        assert {:ok, _csr_der} = Base.decode64(csr)

        conn
        |> Plug.Conn.put_status(202)
        |> Req.Test.json(%{"referenceNumber" => "refresh-reference"})

      "/certificates/enrollments/refresh-reference" ->
        Req.Test.json(conn, %{
          "status" => %{"code" => 200},
          "certificateSerialNumber" => "new-serial"
        })

      "/certificates/retrieve" ->
        assert %{"certificateSerialNumbers" => ["new-serial"]} = conn.body_params

        certificate_der =
          new_certificate
          |> X509.Certificate.from_pem!()
          |> X509.Certificate.to_der()
          |> Base.encode64()

        Req.Test.json(conn, %{"certificates" => [%{"certificate" => certificate_der}]})

      path ->
        if path == "/certificates/#{old_serial_number}/revoke" do
          assert %{"revocationReason" => "Superseded"} = conn.body_params
          Plug.Conn.send_resp(conn, 204, "")
        else
          Plug.Conn.send_resp(conn, 404, "unexpected request: #{path}")
        end
    end
  end

  defp certificate_subject_data do
    %{
      "commonName" => "Firmowid Test",
      "surname" => "Test",
      "serialNumber" => "6161525811",
      "countryName" => "PL",
      "organizationName" => "Firmowid",
      "givenName" => "Kira",
      "uniqueIdentifier" => "test-id",
      "organizationIdentifier" => "VATPL-6161525811"
    }
  end
end
