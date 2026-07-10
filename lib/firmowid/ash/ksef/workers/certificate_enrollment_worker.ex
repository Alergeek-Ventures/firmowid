defmodule Firmowid.Ash.Ksef.Workers.CertificateEnrollmentWorker do
  @moduledoc """
  Authenticates an organization with external XAdES and enrolls a KSeF certificate.

  Each asynchronous boundary is represented by a separate Oban job. Sensitive
  XML, authentication tokens and private keys are encrypted in job arguments.

  Enrollment flow:
      -> authenticate
      -> poll_authentication
      -> submit_certificate_enrollment
      -> poll_certificate_enrollment

  Certificate refresh flow:
      -> refresh_certificate
      -> poll_certificate_refresh
  """

  use Oban.Worker,
    queue: :ksef_sessions,
    max_attempts: 5

  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Ksef.Services.ApiClient
  alias Firmowid.Ash.Ksef.Workers.SessionWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @poll_interval_seconds 5

  @doc "Enqueues the first stage with an encrypted signed XML document."
  @spec enqueue(String.t(), Ash.UUID.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(signed_xml, organization_id) do
    %{
      "action" => "authenticate",
      "organization_id" => organization_id,
      "signed_xml" => encrypt!(signed_xml)
    }
    |> new()
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  @doc "Enqueues automatic rollover for an existing working KSeF certificate credential."
  @spec enqueue_refresh(Credential.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_refresh(%Credential{organization_id: organization_id}) do
    %{
      "action" => "refresh_certificate",
      "organization_id" => organization_id
    }
    |> new()
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{args: %{"action" => action, "organization_id" => organization_id} = args} = job) do
    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :ksef_session},
      tenant: organization_id
    }

    perform_action(action, args, scope, job)
  end

  defp perform_action("authenticate", args, scope, job) do
    case Credential.get_internal!(scope: scope) do
      %Credential{status: :authenticating_epuap} = credential ->
        signed_xml = decrypt!(args["signed_xml"])

        case ApiClient.submit_xades_auth_request(signed_xml) do
          {:ok, operation} ->
            enqueue_stage("poll_authentication", scope.tenant, %{
              "reference_number" => operation.reference_number,
              "authentication_token" => encrypt!(operation.authentication_token)
            })

          {:error, reason} ->
            handle_enrollment_failure(credential, scope, reason, job)
        end

      nil ->
        {:cancel, :no_credentials}

      %Credential{} ->
        {:cancel, :already_connected}
    end
  end

  defp perform_action("poll_authentication", args, scope, job) do
    credential = Credential.get_internal!(scope: scope)
    authentication_token = decrypt!(args["authentication_token"])

    case ApiClient.fetch_auth_status(args["reference_number"], authentication_token) do
      :pending ->
        {:snooze, @poll_interval_seconds}

      :success ->
        case ApiClient.redeem_authentication_token(authentication_token) do
          {:ok, tokens} ->
            Credential.prepare_enrollment!(credential, scope: scope)

            enqueue_stage("submit_certificate_enrollment", scope.tenant, %{
              "access_token" => encrypt!(tokens.access_token)
            })

          {:error, reason} ->
            handle_enrollment_failure(credential, scope, reason, job)
        end

      {:error, reason} ->
        handle_enrollment_failure(credential, scope, reason, job)
    end
  end

  defp perform_action("submit_certificate_enrollment", args, scope, job) do
    credential = Credential.get_internal!(scope: scope)
    access_token = decrypt!(args["access_token"])

    case request_certificate(access_token) do
      {:ok, %{reference_number: reference_number, private_key: private_key}} ->
        Credential.wait_for_certificate!(credential, scope: scope)

        enqueue_stage("poll_certificate_enrollment", scope.tenant, %{
          "reference_number" => reference_number,
          "access_token" => args["access_token"],
          "private_key" => encrypt!(private_key)
        })

      {:error, :certificate_limit_exhausted} ->
        Credential.delete_failed!(credential, :certificate_limit_exhausted, scope: scope)
        {:cancel, :certificate_limit_exhausted}

      {:error, reason} ->
        handle_enrollment_failure(credential, scope, reason, job)
    end
  end

  defp perform_action("refresh_certificate", _args, scope, job) do
    credential = Credential.get_internal!(scope: scope)

    if credential.auth_type in [:certificate, :generated_certificate] do
      access_token = SessionWorker.get_access_token!(scope.tenant)

      with {:ok, %{reference_number: reference_number, private_key: private_key}} <-
             request_certificate(access_token),
           {:ok, _job} <-
             enqueue_stage("poll_certificate_refresh", scope.tenant, %{
               "reference_number" => reference_number,
               "private_key" => encrypt!(private_key)
             }) do
        :ok
      else
        {:error, reason} -> handle_refresh_failure(credential, scope, reason, job)
      end
    else
      Credential.recover_certificate_refresh!(credential, scope: scope)

      {:cancel, :not_certificate_credential}
    end
  end

  defp perform_action("poll_certificate_enrollment", args, scope, job) do
    credential = Credential.get_internal!(scope: scope)
    access_token = decrypt!(args["access_token"])
    reference_number = args["reference_number"]
    private_key = decrypt!(args["private_key"])

    case retrieve_certificate(access_token, reference_number) do
      :pending ->
        {:snooze, @poll_interval_seconds}

      {:ok, certificate} ->
        credentials = certificate_credentials(certificate, private_key)

        with {:ok, _credential} <-
               Credential.complete_certificate_enrollment(credential, credentials, scope: scope),
             :ok <- ApiClient.revoke_refresh_token(access_token) do
          :ok
        else
          {:error, reason} -> handle_enrollment_failure(credential, scope, reason, job)
        end

      {:error, reason} ->
        handle_enrollment_failure(credential, scope, reason, job)
    end
  end

  defp perform_action("poll_certificate_refresh", args, scope, job) do
    credential = Credential.get_internal!(scope: scope)

    access_token = SessionWorker.get_access_token!(scope.tenant)
    reference_number = args["reference_number"]
    private_key = decrypt!(args["private_key"])

    case retrieve_certificate(access_token, reference_number) do
      :pending ->
        {:snooze, @poll_interval_seconds}

      {:ok, certificate} ->
        credentials = certificate_credentials(certificate, private_key)

        case Credential.supersede_certificate(credential, credentials, scope: scope) do
          {:ok, _credential} -> :ok
          {:error, reason} -> handle_refresh_failure(credential, scope, reason, job)
        end

      {:error, reason} ->
        handle_refresh_failure(credential, scope, reason, job)
    end
  end

  defp enqueue_stage(action, organization_id, stage_args) do
    stage_args
    |> Map.merge(%{
      "action" => action,
      "organization_id" => organization_id
    })
    |> new()
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  defp request_certificate(access_token) do
    with {:ok, limits} <- ApiClient.get_certificate_limits(access_token),
         :ok <- validate_limits(limits),
         {:ok, enrollment_data} <- ApiClient.get_certificate_enrollment_data(access_token),
         {:ok, %{csr: csr, private_key: private_key}} <-
           generate_certificate_enrollment(enrollment_data),
         {:ok, reference_number} <-
           ApiClient.submit_certificate_enrollment(
             access_token,
             certificate_name(),
             csr
           ) do
      {:ok, %{reference_number: reference_number, private_key: private_key}}
    end
  end

  defp retrieve_certificate(access_token, reference_number) do
    case ApiClient.get_certificate_enrollment_status(access_token, reference_number) do
      :pending -> :pending
      {:ok, serial_number} -> ApiClient.retrieve_certificate(access_token, serial_number)
      {:error, reason} -> {:error, reason}
    end
  end

  defp certificate_credentials(certificate, private_key) do
    Jason.encode!(%{
      "certificate" => certificate,
      "private_key" => private_key,
      "private_key_password" => nil
    })
  end

  defp validate_limits(%{
         "canRequest" => true,
         "certificate" => %{"remaining" => certificate_remaining},
         "enrollment" => %{"remaining" => enrollment_remaining}
       })
       when certificate_remaining > 0 and enrollment_remaining > 0, do: :ok

  defp validate_limits(_limits), do: {:error, :certificate_limit_exhausted}

  defp generate_certificate_enrollment(enrollment_data) when is_map(enrollment_data) do
    subject =
      certificate_subject_attributes()
      |> Enum.flat_map(&certificate_subject_attributes(enrollment_data, &1))
      |> X509.RDNSequence.new()

    private_key = X509.PrivateKey.new_ec(:secp256r1)
    csr = X509.CSR.new(private_key, subject, hash: :sha256)

    {:ok,
     %{
       csr: csr |> X509.CSR.to_der() |> Base.encode64(),
       private_key: X509.PrivateKey.to_pem(private_key, wrap: true)
     }}
  rescue
    error -> {:error, {:csr_generation_failed, error}}
  end

  defp certificate_subject_attributes do
    [
      {"commonName", :commonName},
      {"surname", :surname},
      {"serialNumber", :serialNumber},
      {"countryName", :countryName},
      {"organizationName", :organizationName},
      {"givenName", :givenName},
      {"uniqueIdentifier", {2, 5, 4, 45}},
      {"organizationIdentifier", {2, 5, 4, 97}}
    ]
  end

  defp certificate_subject_attributes(data, {key, attribute}) do
    data[key]
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(fn value ->
      case attribute do
        oid when is_tuple(oid) -> {oid, {:asn1_OPENTYPE, der_utf8_string(value)}}
        name -> {name, value}
      end
    end)
  end

  defp der_utf8_string(value) when byte_size(value) < 128, do: <<0x0C, byte_size(value), value::binary>>

  defp der_utf8_string(value) when byte_size(value) < 256, do: <<0x0C, 0x81, byte_size(value), value::binary>>

  defp der_utf8_string(value), do: <<0x0C, 0x82, byte_size(value)::16, value::binary>>

  defp certificate_name, do: "Firmowid-#{Date.to_iso8601(Date.utc_today())}"

  defp encrypt!(value), do: value |> Firmowid.Vault.encrypt!() |> Base.encode64()

  defp decrypt!(value), do: value |> Base.decode64!() |> Firmowid.Vault.decrypt!()

  defp retrying?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}), do: attempt < max_attempts

  defp handle_refresh_failure(credential, scope, reason, job) do
    if retrying?(job) do
      {:error, reason}
    else
      Logger.error("KSeF certificate refresh failed for organization #{scope.tenant}: #{inspect(reason)}")

      Credential.recover_certificate_refresh!(credential, scope: scope)

      {:cancel, reason}
    end
  end

  defp handle_enrollment_failure(credential, scope, reason, job) do
    if retrying?(job) do
      {:error, reason}
    else
      Logger.error("KSeF certificate enrollment failed for organization #{scope.tenant}: #{inspect(reason)}")

      Credential.delete_failed!(credential, enrollment_failure_reason(reason), scope: scope)

      {:cancel, reason}
    end
  end

  defp enrollment_failure_reason(:certificate_limit_exhausted), do: :certificate_limit_exhausted
  defp enrollment_failure_reason(_reason), do: :enrollment_failed
end
