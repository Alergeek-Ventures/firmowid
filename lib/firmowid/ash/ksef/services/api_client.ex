defmodule Firmowid.Ash.Ksef.Services.ApiClient do
  @moduledoc """
  HTTP client for the KSeF (Krajowy System e-Faktur) API.

  Handles all direct communication with the KSeF REST API including:
  - Authentication flow (challenge → token → redeem → refresh)
  - Invoice operations (export initiation, status polling, XML retrieval)
  - Online session management (open → send invoice → close)
  - Public key and certificate management (cached via Cachex)

  All authenticated requests use bearer tokens. The client is built on `Req`
  with automatic compression, retries, and a configurable base URL from
  `Application.get_env(:firmowid, :ksef)[:base_url]`.
  """

  alias Firmowid.Ash.Core.Nip
  alias Firmowid.Ash.Ksef.Services.Encryption
  alias Firmowid.Ash.Ksef.Services.XadesSigner

  defp request do
    ksef_config = Application.fetch_env!(:firmowid, :ksef)

    [
      base_url: ksef_config[:base_url],
      user_agent: "Firmowid",
      compressed: true,
      retry: :transient,
      max_retries: 3
    ]
    |> Req.new()
    |> Req.Request.merge_options(ksef_config[:request_options] || [])
  end

  defp request(access_token) when is_binary(access_token) do
    Req.Request.merge_options(request(), auth: {:bearer, access_token})
  end

  defp handle_response({:ok, %{status: 401}}), do: {:error, :unauthorized}
  defp handle_response({:ok, %{status: 403}}), do: {:error, :forbidden}
  defp handle_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_response({:ok, %{status: status, body: body}}), do: {:error, {:unexpected_response, status, body}}

  defp handle_response({:error, reason}), do: {:error, reason}

  @doc "Parses an ISO 8601 datetime string. Raises on invalid input."
  @spec parse_datetime!(String.t()) :: DateTime.t()
  def parse_datetime!(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> dt
      {:error, _} -> raise ArgumentError, "Invalid ISO8601 datetime: #{iso8601}"
    end
  end

  @doc "Extracts the expiration time from a JWT token's payload."
  @spec token_expire_time(String.t()) :: DateTime.t()
  def token_expire_time(jwt_token) when is_binary(jwt_token) do
    payload =
      jwt_token
      |> String.split(".")
      |> Enum.at(1)
      |> Base.url_decode64!(padding: false)
      |> Jason.decode!()

    DateTime.from_unix!(payload["exp"])
  end

  @doc "Returns `true` if the JWT token has expired."
  @spec token_expired?(String.t()) :: boolean()
  def token_expired?(jwt_token) do
    jwt_token
    |> token_expire_time()
    |> DateTime.before?(DateTime.utc_now())
  end

  @doc "Returns the cached KSeF token encryption public key certificate."
  @spec ksef_public_key() :: term()
  def ksef_public_key do
    fetch_public_key_by_usage("KsefTokenEncryption")
  end

  @doc "Returns the cached KSeF symmetric key encryption public key certificate."
  @spec symmetric_key_public_key() :: term()
  def symmetric_key_public_key do
    fetch_public_key_by_usage("SymmetricKeyEncryption")
  end

  defp fetch_public_key_by_usage(usage) do
    cache_key = {:public_key, usage}

    Cachex.fetch!(:ksef, cache_key, fn _key ->
      case fetch_and_parse_public_key(usage) do
        {:ok, cert, valid_to} ->
          expire = DateTime.diff(valid_to, DateTime.utc_now(), :millisecond)
          {:commit, cert, expire: expire}

        {:error, reason} ->
          raise RuntimeError, "Failed to fetch KSeF public key (#{usage}): #{inspect(reason)}"
      end
    end)
  end

  defp fetch_and_parse_public_key(target_usage) do
    with {:ok, %{status: 200, body: certificates}} <-
           Req.get(request(), url: "/security/public-key-certificates"),
         {cert_b64, valid_to} <- find_valid_certificate(certificates, target_usage) do
      cert_b64
      |> Base.decode64!()
      |> X509.Certificate.from_der!(:Certificate)
      |> then(&{:ok, &1, valid_to})
    else
      nil -> {:error, :no_valid_certificate_found}
      response -> handle_response(response)
    end
  end

  defp find_valid_certificate(certificates, target_usage) do
    now = DateTime.utc_now()

    Enum.find_value(certificates, fn
      %{"usage" => [^target_usage]} = cert ->
        valid_from = parse_datetime!(cert["validFrom"])
        valid_to = parse_datetime!(cert["validTo"])

        if DateTime.after?(now, valid_from) and DateTime.before?(now, valid_to) do
          {cert["certificate"], valid_to}
        end

      _ ->
        nil
    end)
  end

  defp prepare_encrypted_token(ksef_token, timestamp) when is_binary(ksef_token) and is_binary(timestamp) do
    timestamp = timestamp |> parse_datetime!() |> DateTime.to_unix(:millisecond)

    "#{ksef_token}|#{timestamp}"
    |> Encryption.encrypt_with_rsa_public_key()
    |> Base.encode64()
  end

  @doc "Authenticates with KSeF using a NIP and encrypted token. Returns access and refresh tokens."
  @spec auth_with_token(String.t(), String.t()) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t()}} | {:error, term()}
  def auth_with_token(context_nip, ksef_token) do
    with {:ok, %{challenge: challenge, timestamp: timestamp}} <- get_auth_challenge(),
         encrypted_token = prepare_encrypted_token(ksef_token, timestamp),
         {:ok,
          %{
            status: 202,
            body: %{"referenceNumber" => reference_number, "authenticationToken" => auth_token}
          }} <-
           Req.post(request(),
             url: "/auth/ksef-token",
             json: %{
               "challenge" => challenge,
               "encryptedToken" => encrypted_token,
               "contextIdentifier" => %{
                 "type" => "Nip",
                 "value" => context_nip
               }
             }
           ),
         :success <- get_auth_status(reference_number, auth_token["token"]) do
      redeem_authentication_token(auth_token["token"])
    else
      response -> handle_response(response)
    end
  end

  @doc """
  Authenticates with KSeF using an XAdES-signed certificate request.

  Returns access and refresh JWTs after the asynchronous KSeF authentication
  operation completes.
  """
  @spec auth_with_ksef_certificate(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t()}} | {:error, term()}
  def auth_with_ksef_certificate(context_nip, certificate, private_key, private_key_password) do
    with :ok <- validate_context_nip(context_nip),
         {:ok, %{challenge: challenge}} <- get_auth_challenge(),
         auth_token_request = prepare_auth_token_request(context_nip, challenge),
         {:ok, signed_auth_token_request} <-
           XadesSigner.sign(
             auth_token_request,
             certificate,
             private_key,
             private_key_password
           ),
         {:ok, %{reference_number: reference_number, authentication_token: auth_token}} <-
           submit_xades_auth_request(signed_auth_token_request),
         :success <- get_auth_status(reference_number, auth_token) do
      redeem_authentication_token(auth_token)
    end
  end

  defp validate_context_nip(context_nip) do
    if is_binary(context_nip) and String.match?(context_nip, ~r/^\d{10}$/) and
         Nip.valid?(context_nip) do
      :ok
    else
      {:error, :invalid_context_nip}
    end
  end

  @doc "Builds an unsigned KSeF AuthTokenRequest XML for a NIP context."
  @spec prepare_auth_token_request(String.t(), String.t()) :: String.t()
  def prepare_auth_token_request(context_nip, challenge) do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <AuthTokenRequest xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://ksef.mf.gov.pl/auth/token/2.0">
        <Challenge>#{challenge}</Challenge>
        <ContextIdentifier>
            <Nip>#{context_nip}</Nip>
        </ContextIdentifier>
        <SubjectIdentifierType>certificateSubject</SubjectIdentifierType>
    </AuthTokenRequest>
    """
  end

  @doc "Fetches a fresh KSeF authentication challenge."
  @spec get_auth_challenge() ::
          {:ok, %{challenge: String.t(), timestamp: String.t()}} | {:error, term()}
  def get_auth_challenge do
    case Req.post(request(), url: "/auth/challenge") do
      {:ok, %{status: 200, body: %{"challenge" => challenge, "timestamp" => timestamp}}} ->
        {:ok, %{challenge: challenge, timestamp: timestamp}}

      response ->
        handle_response(response)
    end
  end

  @doc "Submits an externally signed XAdES AuthTokenRequest."
  @spec submit_xades_auth_request(String.t()) ::
          {:ok, %{reference_number: String.t(), authentication_token: String.t()}}
          | {:error, term()}
  def submit_xades_auth_request(signed_xml) when is_binary(signed_xml) do
    case Req.post(request(),
           url: "/auth/xades-signature",
           params: [verifyCertificateChain: false],
           body: signed_xml,
           headers: [{"content-type", "application/xml"}, {"accept", "application/json"}]
         ) do
      {:ok,
       %{
         status: 202,
         body: %{
           "referenceNumber" => reference_number,
           "authenticationToken" => %{"token" => authentication_token}
         }
       }} ->
        {:ok,
         %{
           reference_number: reference_number,
           authentication_token: authentication_token
         }}

      response ->
        handle_response(response)
    end
  end

  @doc "Fetches one authentication operation status without polling."
  @spec fetch_auth_status(String.t(), String.t()) ::
          :pending | :success | {:error, term()}
  def fetch_auth_status(reference_number, authentication_token) do
    case Req.get(request(authentication_token), url: "/auth/#{reference_number}") do
      {:ok, %{status: 200, body: %{"status" => %{"code" => 100}}}} ->
        :pending

      {:ok, %{status: 200, body: %{"status" => %{"code" => 200}}}} ->
        :success

      {:ok, %{status: 200, body: %{"status" => status}}} ->
        {:error, {:authentication_failed, status}}

      response ->
        handle_response(response)
    end
  end

  @doc "Redeems a completed authentication operation for access and refresh tokens."
  @spec redeem_authentication_token(String.t()) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t()}} | {:error, term()}
  def redeem_authentication_token(authentication_token) do
    case Req.post(request(authentication_token), url: "/auth/token/redeem") do
      {:ok,
       %{
         status: 200,
         body: %{
           "accessToken" => %{"token" => access_token},
           "refreshToken" => %{"token" => refresh_token}
         }
       }} ->
        {:ok, %{access_token: access_token, refresh_token: refresh_token}}

      response ->
        handle_response(response)
    end
  end

  @doc """
  Refreshes an access token using the provided refresh token.
  Does not return a new refresh token.
  """
  @spec refresh_session(String.t() | nil) ::
          {:ok, String.t()} | {:error, :refresh_token_expired | term()}
  def refresh_session(refresh_token) do
    if is_nil(refresh_token) or token_expired?(refresh_token) do
      {:error, :refresh_token_expired}
    else
      case Req.post(request(refresh_token), url: "/auth/token/refresh") do
        {:ok, %{status: 200, body: %{"accessToken" => %{"token" => access_token}}}} ->
          {:ok, access_token}

        {:ok, %{status: 401}} ->
          {:error, :refresh_token_expired}

        response ->
          handle_response(response)
      end
    end
  end

  @doc "Invalidates the KSeF authentication session associated with the provided token. Token can be either access or refresh token."
  @spec revoke_refresh_token(String.t()) :: :ok | {:error, term()}
  def revoke_refresh_token(token) when is_binary(token) do
    case Req.delete(request(token), url: "/auth/sessions/current") do
      {:ok, %{status: status}} when status in [204, 401] -> :ok
      response -> handle_response(response)
    end
  end

  @doc "Polls the authentication status for a given reference number."
  @spec get_auth_status(String.t(), String.t()) :: :success | {:error, term()}
  def get_auth_status(reference_number, auth_token) do
    config = Application.fetch_env!(:firmowid, :ksef)
    max_attempts = config[:auth_status_max_attempts] || 30
    interval = config[:auth_status_poll_interval_ms] || 1_000

    poll_auth_status(reference_number, auth_token, max_attempts, interval)
  end

  defp poll_auth_status(_reference_number, _auth_token, 0, _interval), do: {:error, :auth_status_timeout}

  defp poll_auth_status(reference_number, auth_token, attempts_left, interval) do
    case fetch_auth_status(reference_number, auth_token) do
      :success ->
        :success

      :pending ->
        if interval > 0, do: Process.sleep(interval)
        poll_auth_status(reference_number, auth_token, attempts_left - 1, interval)

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Returns KSeF certificate and enrollment limits."
  @spec get_certificate_limits(String.t()) :: {:ok, map()} | {:error, term()}
  def get_certificate_limits(access_token) do
    authenticated_get(access_token, "/certificates/limits")
  end

  @doc "Returns the exact distinguished-name data required for a certificate CSR."
  @spec get_certificate_enrollment_data(String.t()) :: {:ok, map()} | {:error, term()}
  def get_certificate_enrollment_data(access_token) do
    authenticated_get(access_token, "/certificates/enrollments/data")
  end

  @doc "Submits a KSeF authentication-certificate enrollment."
  @spec submit_certificate_enrollment(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def submit_certificate_enrollment(access_token, certificate_name, csr) do
    case Req.post(request(access_token),
           url: "/certificates/enrollments",
           json: %{
             "certificateName" => certificate_name,
             "certificateType" => "Authentication",
             "csr" => csr
           }
         ) do
      {:ok, %{status: 202, body: %{"referenceNumber" => reference_number}}} ->
        {:ok, reference_number}

      response ->
        handle_response(response)
    end
  end

  @doc "Fetches one certificate enrollment status without polling."
  @spec get_certificate_enrollment_status(String.t(), String.t()) ::
          :pending | {:ok, String.t()} | {:error, term()}
  def get_certificate_enrollment_status(access_token, reference_number) do
    case Req.get(request(access_token), url: "/certificates/enrollments/#{reference_number}") do
      {:ok, %{status: 200, body: %{"status" => %{"code" => 100}}}} ->
        :pending

      {:ok,
       %{
         status: 200,
         body: %{
           "status" => %{"code" => 200},
           "certificateSerialNumber" => serial_number
         }
       }} ->
        {:ok, serial_number}

      {:ok, %{status: 200, body: %{"status" => status}}} ->
        {:error, {:certificate_enrollment_failed, status}}

      response ->
        handle_response(response)
    end
  end

  @doc "Retrieves one issued KSeF certificate as PEM."
  @spec retrieve_certificate(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def retrieve_certificate(access_token, serial_number) do
    case Req.post(request(access_token),
           url: "/certificates/retrieve",
           json: %{"certificateSerialNumbers" => [serial_number]}
         ) do
      {:ok,
       %{
         status: 200,
         body: %{"certificates" => [%{"certificate" => certificate_der} | _]}
       }} ->
        parse_certificate(certificate_der)

      {:ok, %{status: 200, body: %{"certificates" => []}}} ->
        {:error, :certificate_not_returned}

      response ->
        handle_response(response)
    end
  end

  @doc "Revokes a KSeF certificate by its hexadecimal serial number."
  @spec revoke_certificate(String.t(), String.t(), :unspecified | :superseded) ::
          :ok | {:error, term()}
  def revoke_certificate(access_token, serial_number, reason) do
    body = %{
      "revocationReason" =>
        case reason do
          :unspecified -> "Unspecified"
          :superseded -> "Superseded"
        end
    }

    case Req.post(request(access_token),
           url: "/certificates/#{serial_number}/revoke",
           json: body
         ) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok,
       %{
         status: 400,
         body: %{"exception" => %{"exceptionDetailList" => [%{"exceptionCode" => 25_009}]}}
       }} ->
        # 25009 = Certificate is already revoked
        :ok

      response ->
        handle_response(response)
    end
  end

  defp parse_certificate(certificate_der) do
    with {:ok, der} <- Base.decode64(certificate_der) do
      {:ok, der |> X509.Certificate.from_der!() |> X509.Certificate.to_pem()}
    end
  rescue
    _error -> {:error, :invalid_certificate}
  end

  defp authenticated_get(access_token, url) do
    case Req.get(request(access_token), url: url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      response ->
        handle_response(response)
    end
  end

  @doc """
  Initiates an invoice export with encryption. Returns the export reference number.

  The `filters` map must include `"subjectType"` and `"dateRange"`. The `"dateRange"`
  should use `"PermanentStorage"` date type for reliable incremental sync, and
  `"restrictToPermanentStorageHwmDate"` should be `true` to activate HWM-based
  completeness guarantees from KSeF.
  """
  @spec initiate_invoice_export(String.t(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  def initiate_invoice_export(access_token, filters, encryption_info) do
    request_body = %{
      "filters" => filters,
      "encryption" => encryption_info
    }

    case Req.post(request(access_token),
           url: "/invoices/exports",
           json: request_body
         ) do
      {:ok, %{status: 201, body: %{"referenceNumber" => reference_number}}} ->
        {:ok, reference_number}

      response ->
        handle_response(response)
    end
  end

  @doc "Checks the status of an export operation. Returns the package on completion."
  @spec get_export_status(String.t(), String.t()) :: {:ok, map()} | :pending | {:error, term()}
  def get_export_status(access_token, reference_number) do
    access_token
    |> request()
    |> Req.get(url: "/invoices/exports/#{reference_number}")
    |> case do
      {:ok, %{status: 200, body: %{"status" => %{"code" => status_code}} = body}} ->
        case status_code do
          100 -> :pending
          200 -> {:ok, body["package"]}
          210 -> {:error, :expired}
          500 -> {:error, :retry}
          _ -> {:error, body["status"]}
        end

      response ->
        handle_response(response)
    end
  end

  @doc "Fetches FA XML invoice by KSeF number. Rate limit: 64 req/h."
  @spec get_invoice_xml(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def get_invoice_xml(access_token, ksef_number) when is_binary(ksef_number) do
    encoded_number = URI.encode(ksef_number)

    case Req.get(request(access_token),
           url: "/invoices/ksef/#{encoded_number}",
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      response ->
        handle_response(response)
    end
  end

  # ============================================================================
  # Online Session and Invoice Submission (KSeF API v2.0)
  # ============================================================================

  @doc """
  Opens an online session for submitting invoices.

  Returns `{:ok, %{session_reference: string, encryption_key: binary, encryption_iv: binary}}`
  on success, or `{:error, reason}` on failure.

  The session uses FA(3) schema version 1-0E for invoice submission.
  """
  @spec open_online_session(String.t()) ::
          {:ok, %{session_reference: String.t(), encryption_key: binary(), encryption_iv: binary()}}
          | {:error, term()}
  def open_online_session(access_token) do
    encryption_data = Encryption.generate_encryption_data()

    request_body = %{
      "formCode" => %{
        "systemCode" => "FA (3)",
        "schemaVersion" => "1-0E",
        "value" => "FA"
      },
      "encryption" => %{
        "encryptedSymmetricKey" => encryption_data.key |> Encryption.encrypt_symmetric_key() |> Base.encode64(),
        "initializationVector" => Base.encode64(encryption_data.iv)
      }
    }

    case Req.post(request(access_token),
           url: "/sessions/online",
           json: request_body
         ) do
      {:ok, %{status: 201, body: %{"referenceNumber" => reference_number}}} ->
        {:ok,
         %{
           session_reference: reference_number,
           encryption_key: encryption_data.key,
           encryption_iv: encryption_data.iv
         }}

      response ->
        handle_response(response)
    end
  end

  @doc """
  Sends an invoice within an active online session.

  The `invoice_xml` should be the raw XML string of the invoice in FA(3) format.
  The function will encrypt the invoice and send it to KSeF.

  Returns `{:ok, invoice_reference}` on success.
  """
  @spec send_invoice(
          String.t(),
          %{session_reference: String.t(), encryption_key: binary(), encryption_iv: binary()},
          binary()
        ) ::
          {:ok, String.t()} | {:error, term()}
  def send_invoice(
        access_token,
        %{session_reference: session_reference, encryption_key: encryption_key, encryption_iv: encryption_iv},
        invoice_xml
      ) do
    invoice_hash = :sha256 |> :crypto.hash(invoice_xml) |> Base.encode64()
    invoice_size = byte_size(invoice_xml)

    encrypted_invoice = Encryption.encrypt_aes256_cbc(invoice_xml, encryption_key, encryption_iv)
    encrypted_invoice_hash = :sha256 |> :crypto.hash(encrypted_invoice) |> Base.encode64()
    encrypted_invoice_size = byte_size(encrypted_invoice)
    encrypted_invoice_content = Base.encode64(encrypted_invoice)

    request_body = %{
      "invoiceHash" => invoice_hash,
      "invoiceSize" => invoice_size,
      "encryptedInvoiceHash" => encrypted_invoice_hash,
      "encryptedInvoiceSize" => encrypted_invoice_size,
      "encryptedInvoiceContent" => encrypted_invoice_content,
      "offlineMode" => false
    }

    case Req.post(request(access_token),
           url: "/sessions/online/#{session_reference}/invoices",
           json: request_body
         ) do
      {:ok, %{status: 202, body: %{"referenceNumber" => invoice_reference}}} ->
        {:ok, invoice_reference}

      response ->
        handle_response(response)
    end
  end

  @doc """
  Gets the status of a submitted invoice within a session.

  Returns:
  - `{:ok, %{ksef_number: string, status: map}}` when invoice is fully processed
  - `:pending` when invoice is still being processed
  - `{:error, reason}` on failure
  """
  @spec get_invoice_status(String.t(), String.t(), String.t()) ::
          {:ok, %{ksef_number: String.t(), acquisition_date: String.t(), invoice_hash: String.t()}}
          | :pending
          | :retry
          | {:error, term()}
  def get_invoice_status(access_token, session_reference, invoice_reference) do
    case Req.get(request(access_token),
           url: "/sessions/#{session_reference}/invoices/#{invoice_reference}"
         ) do
      {:ok, %{status: 200, body: %{"status" => %{"code" => 200}} = body}} ->
        {:ok,
         %{
           ksef_number: body["ksefNumber"],
           acquisition_date: body["acquisitionDate"],
           invoice_hash: body["invoiceHash"]
         }}

      {:ok, %{status: 200, body: %{"status" => %{"code" => code}}}} when code in [100, 150] ->
        # 100 = accepted for processing, 150 = processing in progress
        :pending

      {:ok, %{status: 200, body: %{"status" => %{"code" => 440} = status}}} ->
        original_ksef_number = status["extensions"]["originalKsefNumber"]
        original_session_reference = status["extensions"]["originalSessionReferenceNumber"]

        {:error, {:invoice_duplicate, original_ksef_number, original_session_reference}}

      {:ok, %{status: 200, body: %{"status" => %{"code" => 550}}}} ->
        # 550 means cancelled by server and should be retried
        :retry

      {:ok, %{status: 200, body: %{"status" => %{"code" => code} = status}}} ->
        {:error, {:invoice_processing_failed, code, status}}

      response ->
        handle_response(response)
    end
  end

  @doc """
  Closes an online session.

  Should be called after all invoices have been submitted within the session.
  """
  @spec close_online_session(String.t(), String.t()) :: :ok | {:error, term()}
  def close_online_session(access_token, session_reference) do
    case Req.post(request(access_token), url: "/sessions/online/#{session_reference}/close") do
      {:ok, %{status: 204}} ->
        :ok

      response ->
        handle_response(response)
    end
  end
end
