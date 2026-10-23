defmodule Firmowid.Ash.Ksef.Workers.CertificateEnrollmentWorkerTest do
  @moduledoc false

  use Firmowid.DataCase, async: false

  import Ecto.Query
  import Firmowid.AccountsFixtures
  import Firmowid.Ash.Ksef.KsefTestHelpers, only: [jwt: 1]

  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Ksef.CredentialMetadata
  alias Firmowid.Ash.Ksef.Workers.CertificateEnrollmentWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Repo

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

  test "replaces and revokes a generated certificate after KSeF issues its successor", %{
    organization_id: organization_id,
    scope: scope
  } do
    {old_certificate, old_private_key} = certificate_material("Old certificate")
    {new_certificate, _new_private_key} = certificate_material("New certificate")

    credential =
      seed_working_credential(
        organization_id,
        old_certificate,
        old_private_key,
        :generated_certificate
      )

    old_serial_number = CredentialMetadata.certificate_serial_number(credential)

    Req.Test.stub(
      :ksef_certificate_refresh_api,
      &successful_refresh_response(&1, new_certificate, old_serial_number)
    )

    assert {:ok, %Credential{status: :refreshing}} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Credential.refresh_certificate(credential, scope: scope)
             end)

    assert :ok =
             Oban.Testing.with_testing_mode(:manual, fn ->
               perform_job(CertificateEnrollmentWorker, refresh_args(organization_id))
             end)

    poll_args = queued_poll_args(organization_id)
    assert poll_args["credential_id"] == credential.id
    assert poll_args["refresh_started_at"]

    assert :ok = perform_job(CertificateEnrollmentWorker, poll_args)

    refreshed_credential = Credential.get_internal!(scope: scope)
    assert refreshed_credential.status == :working
    assert refreshed_credential.auth_type == :generated_certificate

    assert %{"certificate" => refreshed_certificate, "private_key" => refreshed_private_key} =
             Jason.decode!(refreshed_credential.credentials)

    assert String.trim_trailing(refreshed_certificate) == String.trim_trailing(new_certificate)
    assert refreshed_private_key != old_private_key
    assert refreshed_credential.expires_on == certificate_expiration_date(new_certificate)
  end

  test "cancels stale refresh jobs after credentials are removed", %{
    organization_id: organization_id
  } do
    assert {:cancel, :no_credentials} =
             perform_job(CertificateEnrollmentWorker, refresh_args(organization_id))
  end

  test "does not revoke an uploaded certificate after rollover", %{
    organization_id: organization_id,
    scope: scope
  } do
    {certificate, key} = certificate_material("Uploaded certificate")
    {successor, _key} = certificate_material("Successor")
    credential = seed_working_credential(organization_id, certificate, key, :certificate)
    serial = CredentialMetadata.certificate_serial_number(credential)

    Req.Test.stub(:ksef_certificate_refresh_api, fn conn ->
      refute String.ends_with?(conn.request_path, "/revoke")
      successful_refresh_response(conn, successor, serial)
    end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      Credential.refresh_certificate!(credential, scope: scope)
      assert %{success: 1} = Oban.drain_queue(queue: :ksef_sessions)
      assert %{success: 1} = Oban.drain_queue(queue: :ksef_sessions)
      assert Credential.get_internal!(scope: scope).auth_type == :generated_certificate
      assert Credential.get_internal!(scope: scope).status == :working
    end)
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

  test "disconnect cancels a real retryable certificate poll", %{
    organization_id: organization_id,
    scope: scope,
    admin: admin
  } do
    {certificate, key} = certificate_material("Current certificate")

    credential =
      seed_working_credential(organization_id, certificate, key, :generated_certificate)

    serial = CredentialMetadata.certificate_serial_number(credential)
    revoke_path = "/certificates/#{serial}/revoke"

    Req.Test.stub(:ksef_certificate_refresh_api, fn conn ->
      case conn.request_path do
        "/certificates/enrollments/refresh-reference" ->
          Plug.Conn.send_resp(conn, 403, "unavailable")

        "/auth/sessions/current" ->
          Plug.Conn.send_resp(conn, 204, "")

        ^revoke_path ->
          assert %{"revocationReason" => "Unspecified"} = conn.body_params
          Plug.Conn.send_resp(conn, 204, "")

        _ ->
          successful_refresh_response(conn, certificate, serial)
      end
    end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      Credential.refresh_certificate!(credential, scope: scope)
      assert %{success: 1} = Oban.drain_queue(queue: :ksef_sessions)
      assert %{failure: 1} = Oban.drain_queue(queue: :ksef_sessions)
      poll = queued_poll_job(organization_id)
      assert poll.state == "retryable"
      assert DateTime.after?(poll.scheduled_at, DateTime.utc_now())

      assert {:ok, :disconnected} =
               Ksef.unauthenticate(%Scope{actor: admin, tenant: organization_id})

      assert Repo.get!(Oban.Job, poll.id, oban_jobs: true).state == "cancelled"
      assert Credential.get_internal!(scope: scope) == nil
    end)
  end

  for legacy? <- [false, true] do
    @tag legacy?: legacy?
    test "rejects a stale #{if legacy?, do: "legacy", else: "bound"} poll from an earlier refresh",
         %{
           organization_id: organization_id,
           scope: scope,
           legacy?: legacy?
         } do
      {certificate, key} = certificate_material("Current certificate")

      credential =
        seed_working_credential(organization_id, certificate, key, :generated_certificate)

      serial = CredentialMetadata.certificate_serial_number(credential)

      Req.Test.stub(
        :ksef_certificate_refresh_api,
        &successful_refresh_response(&1, certificate, serial)
      )

      Oban.Testing.with_testing_mode(:manual, fn ->
        refreshing = Credential.refresh_certificate!(credential, scope: scope)
        assert %{success: 1} = Oban.drain_queue(queue: :ksef_sessions)
        poll = queued_poll_job(organization_id)
        working = Credential.recover_certificate_refresh!(refreshing, scope: scope)
        current = Credential.refresh_certificate!(working, scope: scope)

        args =
          if legacy?,
            do: Map.drop(poll.args, ["credential_id", "refresh_started_at"]),
            else: poll.args

        Req.Test.stub(:ksef_certificate_refresh_api, fn _ -> flunk("stale poll reached KSeF") end)

        expected_reason =
          if legacy?, do: :unbound_certificate_refresh_restarted, else: :stale_certificate_refresh

        assert {:cancel, ^expected_reason} =
                 perform_job(CertificateEnrollmentWorker, args, inserted_at: poll.inserted_at)

        assert Credential.get_internal!(scope: scope).credentials == current.credentials
        assert Credential.get_internal!(scope: scope).status == :refreshing
      end)
    end
  end

  test "restarts an already queued legacy poll without stranding the current refresh", %{
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
      poll = queued_poll_job(organization_id)
      args = Map.drop(poll.args, ["credential_id", "refresh_started_at"])

      assert {:cancel, :unbound_certificate_refresh_restarted} =
               perform_job(CertificateEnrollmentWorker, args, inserted_at: poll.inserted_at)

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
    queued_poll_job(organization_id).args
  end

  defp queued_poll_job(organization_id) do
    query =
      from job in Oban.Job,
        where:
          job.worker == "Firmowid.Ash.Ksef.Workers.CertificateEnrollmentWorker" and
            fragment("?->>'action'", job.args) == "poll_certificate_refresh" and
            fragment("?->>'organization_id'", job.args) == ^organization_id

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
