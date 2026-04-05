defmodule Firmowid.Ash.Ksef.Services.ApiClient do
  @moduledoc false

  alias Firmowid.Ash.Ksef.Services.Encryption

  defp request do
    Req.new(
      base_url: Application.fetch_env!(:firmowid, :ksef)[:base_url],
      user_agent: "Firmowid",
      compressed: true,
      retry: :transient,
      max_retries: 3
    )
  end

  defp request(access_token) when is_binary(access_token) do
    Req.Request.merge_options(request(), auth: {:bearer, access_token})
  end

  def parse_datetime!(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> dt
      {:error, _} -> raise "Invalid ISO8601 datetime: #{iso8601}"
    end
  end

  def token_expire_time(jwt_token) when is_binary(jwt_token) do
    payload =
      jwt_token
      |> String.split(".")
      |> Enum.at(1)
      |> Base.url_decode64!(padding: false)
      |> Jason.decode!()

    DateTime.from_unix!(payload["exp"])
  end

  def token_expired?(jwt_token) do
    jwt_token
    |> token_expire_time()
    |> DateTime.before?(DateTime.utc_now())
  end

  def ksef_public_key do
    fetch_public_key_by_usage("KsefTokenEncryption")
  end

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
          raise "Failed to fetch KSeF public key (#{usage}): #{inspect(reason)}"
      end
    end)
  end

  defp fetch_and_parse_public_key(target_usage) do
    with {:ok, %{body: certificates}} <-
           Req.get(request(), url: "/security/public-key-certificates"),
         {cert_b64, valid_to} <- find_valid_certificate(certificates, target_usage) do
      cert_b64
      |> Base.decode64!()
      |> X509.Certificate.from_der!(:Certificate)
      |> then(&{:ok, &1, valid_to})
    else
      nil -> {:error, :no_valid_certificate_found}
      {:error, _} = error -> error
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

  def auth(context_nip, ksef_token) do
    with {:ok, %{body: %{"challenge" => challenge, "timestamp" => timestamp}}} <-
           Req.post(request(), url: "/auth/challenge"),
         {:ok, %{body: %{"referenceNumber" => reference_number, "authenticationToken" => auth_token}}} <-
           Req.post(request(),
             url: "/auth/ksef-token",
             json: %{
               "challenge" => challenge,
               "encryptedToken" => prepare_encrypted_token(ksef_token, timestamp),
               "contextIdentifier" => %{
                 "type" => "Nip",
                 "value" => context_nip
               }
             }
           ),
         :success <- get_auth_status(reference_number, auth_token["token"]),
         {:ok, %{body: body}} <-
           Req.post(request(auth_token["token"]), url: "/auth/token/redeem") do
      {:ok,
       %{
         access_token: body["accessToken"]["token"],
         refresh_token: body["refreshToken"]["token"]
       }}
    end
  end

  @doc """
  Refresh an access token using the provided refresh token.
  DOES NOT return a new refresh token.
  """
  def refresh_session(refresh_token) do
    if is_nil(refresh_token) or token_expired?(refresh_token) do
      {:error, :refresh_token_expired}
    else
      case Req.post(request(refresh_token), url: "/auth/token/refresh") do
        {:ok, %{status: 200, body: %{"accessToken" => %{"token" => access_token}}}} ->
          {:ok, access_token}

        {:ok, %{status: 401}} ->
          {:error, :refresh_token_expired}

        {:error, _reason} = result ->
          result
      end
    end
  end

  def get_auth_status(reference_number, auth_token) do
    auth_token
    |> request()
    |> retry_request()
    |> Req.get(
      url: "/auth/#{reference_number}",
      retry: fn
        # status code 100 means "in progress"
        _req, res ->
          match?(%Req.Response{status: 200, body: %{"status" => %{"code" => 100}}}, res)
      end
    )
    |> case do
      {:ok, %{body: %{"status" => %{"code" => 200}}}} -> :success
      {:ok, %{body: body}} -> {:error, body}
      rest -> rest
    end
  end

  @doc """
  Initiate an invoice export with encryption.
  """
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

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check status of an export operation.
  """
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

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches FA XML invoice by KSeF number.
  Rate limit 64 req/h
  """
  def get_invoice_xml(access_token, ksef_number) when is_binary(ksef_number) do
    encoded_number = URI.encode(ksef_number)

    case Req.get(request(access_token),
           url: "/invoices/ksef/#{encoded_number}",
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
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

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends an invoice within an active online session.

  The `invoice_xml` should be the raw XML string of the invoice in FA(3) format.
  The function will encrypt the invoice and send it to KSeF.

  Returns `{:ok, invoice_reference}` on success.
  """
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

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the status of a submitted invoice within a session.

  Returns:
  - `{:ok, %{ksef_number: string, status: map}}` when invoice is fully processed
  - `:pending` when invoice is still being processed
  - `{:error, reason}` on failure
  """
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

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Closes an online session.

  Should be called after all invoices have been submitted within the session.
  """
  def close_online_session(access_token, session_reference) do
    case Req.post(request(access_token), url: "/sessions/online/#{session_reference}/close") do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Moves retry step to the end of the response steps in order
  # to have access to decoded response body in the retry function.
  defp retry_request(request) do
    Req.Request.append_response_steps(
      %{request | response_steps: Enum.reject(request.response_steps, &match?({:retry, _}, &1))},
      retry: &Req.Steps.retry/1
    )
  end
end
