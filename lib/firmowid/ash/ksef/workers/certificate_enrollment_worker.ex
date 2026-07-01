defmodule Firmowid.Ash.Ksef.Workers.CertificateEnrollmentWorker do
  @moduledoc """
  Authenticates an organization with external XAdES and enrolls a KSeF certificate.

  Each asynchronous boundary is represented by a separate Oban job. Sensitive
  XML, authentication tokens and private keys are encrypted in job arguments.
  """

  use Oban.Worker,
    queue: :ksef_sessions,
    max_attempts: 5

  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Services.ApiClient
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
      "signed_xml" => signed_xml
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

    if Ksef.get_credential(scope) do
      {:cancel, :already_connected}
    else
      perform_action(action, args, scope, job)
    end
  end

  defp perform_action("authenticate", args, scope, job) do
    Ksef.broadcast_ksef_certificate_status(scope.tenant, :authenticating)

    case ApiClient.submit_xades_auth_request(args["signed_xml"]) do
      {:ok, operation} ->
        enqueue_stage("poll_authentication", scope.tenant, %{
          "reference_number" => operation.reference_number,
          "authentication_token" => encrypt!(operation.authentication_token)
        })

      {:error, reason} ->
        retry_or_fail(scope, reason, job)
    end
  end

  defp perform_action("poll_authentication", args, scope, job) do
    authentication_token = decrypt!(args["authentication_token"])

    case ApiClient.fetch_auth_status(args["reference_number"], authentication_token) do
      :pending ->
        {:snooze, @poll_interval_seconds}

      :success ->
        case ApiClient.redeem_authentication_token(authentication_token) do
          {:ok, tokens} ->
            enqueue_stage("submit_certificate_enrollment", scope.tenant, %{
              "tokens" => encrypt_json!(tokens)
            })

          {:error, reason} ->
            retry_or_fail(scope, reason, job)
        end

      {:error, reason} ->
        retry_or_fail(scope, reason, job)
    end
  end

  defp perform_action("submit_certificate_enrollment", args, scope, job) do
    Ksef.broadcast_ksef_certificate_status(scope.tenant, :preparing_certificate)

    tokens = decrypt_json!(args["tokens"])

    with {:ok, limits} <- ApiClient.get_certificate_limits(tokens["access_token"]),
         :ok <- validate_limits(limits),
         {:ok, enrollment_data} <-
           ApiClient.get_certificate_enrollment_data(tokens["access_token"]),
         {:ok, %{csr: csr, private_key: private_key}} <-
           generate_certificate_enrollment(enrollment_data),
         {:ok, reference_number} <-
           ApiClient.submit_certificate_enrollment(
             tokens["access_token"],
             certificate_name(),
             csr
           ) do
      enqueue_stage("poll_certificate_enrollment", scope.tenant, %{
        "reference_number" => reference_number,
        "tokens" => args["tokens"],
        "private_key" => encrypt!(private_key)
      })
    else
      {:error, :certificate_limit_exhausted} ->
        Ksef.broadcast_ksef_certificate_status(
          scope.tenant,
          :failed,
          :certificate_limit_exhausted
        )

        {:cancel, :certificate_limit_exhausted}

      {:error, reason} ->
        retry_or_fail(scope, reason, job)
    end
  end

  defp perform_action("poll_certificate_enrollment", args, scope, job) do
    Ksef.broadcast_ksef_certificate_status(scope.tenant, :waiting_for_certificate)

    access_token = decrypt_json!(args["tokens"])["access_token"]
    reference_number = args["reference_number"]
    private_key = decrypt!(args["private_key"])

    case ApiClient.get_certificate_enrollment_status(access_token, reference_number) do
      :pending ->
        {:snooze, @poll_interval_seconds}

      {:ok, serial_number} ->
        persist_certificate(serial_number, access_token, private_key, scope, job)

      {:error, reason} ->
        retry_or_fail(scope, reason, job)
    end
  end

  defp persist_certificate(serial_number, access_token, private_key, scope, job) do
    with {:ok, certificate} <- ApiClient.retrieve_certificate(access_token, serial_number),
         {:ok, credential} <-
           Ksef.authenticate_with_ksef_certificate(certificate, private_key, nil, scope) do
      Ksef.broadcast_ksef_certificate_status(scope.tenant, :connected)
      {:ok, credential}
    else
      {:error, reason} -> retry_or_fail(scope, reason, job)
    end
  end

  defp enqueue_stage(action, organization_id, stage_args) do
    stage_args
    |> Map.merge(%{"action" => action, "organization_id" => organization_id})
    |> new()
    |> Firmowid.Oban.insert(skip_organization_id: true)
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

  defp encrypt_json!(value), do: value |> Jason.encode!() |> encrypt!()

  defp decrypt_json!(value), do: value |> decrypt!() |> Jason.decode!()

  defp retry_or_fail(_scope, reason, %Oban.Job{attempt: attempt, max_attempts: max_attempts}) when attempt < max_attempts,
    do: {:error, reason}

  defp retry_or_fail(scope, reason, %Oban.Job{}) do
    Logger.error("KSeF certificate enrollment failed for organization #{scope.tenant}: #{inspect(reason)}")

    Ksef.broadcast_ksef_certificate_status(scope.tenant, :failed, reason)
    {:cancel, reason}
  end
end
