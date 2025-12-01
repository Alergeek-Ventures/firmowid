defmodule Firmowid.Ksef.ApiClient do
  @moduledoc false

  alias Firmowid.Ksef.Encryption

  require Logger

  defp request do
    Req.new(
      base_url: Application.fetch_env!(:firmowid, :ksef)[:base_url],
      user_agent: "Firmowid",
      compressed: true
    )
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
    case Req.get(request(), url: "/security/public-key-certificates") do
      {:ok, %{body: certificates}} ->
        certificate =
          Enum.find_value(certificates, fn
            %{"usage" => [^target_usage]} = certificate ->
              now = DateTime.utc_now()
              valid_from = parse_datetime!(certificate["validFrom"])
              valid_to = parse_datetime!(certificate["validTo"])

              if DateTime.after?(now, valid_from) and DateTime.before?(now, valid_to) do
                {certificate["certificate"], valid_to}
              end

            _ ->
              nil
          end)

        case certificate do
          nil ->
            {:error, :no_valid_certificate_found}

          {certificate, valid_to} ->
            certificate
            |> Base.decode64!()
            |> X509.Certificate.from_der!(:Certificate)
            |> then(&{:ok, &1, valid_to})
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_encrypted_token(ksef_token, timestamp) when is_binary(ksef_token) and is_binary(timestamp) do
    timestamp = timestamp |> parse_datetime!() |> DateTime.to_unix(:millisecond)

    "#{ksef_token}|#{timestamp}"
    |> Encryption.encrypt_with_rsa_public_key()
    |> Base.encode64()
  end

  def auth(context_nip, ksef_token) do
    %{"challenge" => challenge, "timestamp" => timestamp} =
      Req.post!(request(), url: "/auth/challenge").body

    %{"referenceNumber" => reference_number, "authenticationToken" => auth_token} =
      Req.post!(request(),
        url: "/auth/ksef-token",
        json: %{
          "challenge" => challenge,
          "encryptedToken" => prepare_encrypted_token(ksef_token, timestamp),
          "contextIdentifier" => %{
            "type" => "Nip",
            "value" => context_nip
          }
        }
      ).body

    case get_auth_status(reference_number, auth_token["token"]) do
      :success ->
        body =
          Req.post!(request(), url: "/auth/token/redeem", auth: {:bearer, auth_token["token"]}).body

        {:ok,
         %{
           access_token: body["accessToken"]["token"],
           refresh_token: body["refreshToken"]["token"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refresh an access token using the provided refresh token.
  DOES NOT return a new refresh token.
  """
  def refresh_session(refresh_token) when is_binary(refresh_token) do
    if token_expired?(refresh_token) do
      {:error, :refresh_token_expired}
    else
      case Req.post(request(), url: "/auth/token/refresh", auth: {:bearer, refresh_token}) do
        {:ok, %{status: 200, body: %{"accessToken" => %{"token" => access_token}}}} ->
          {:ok, access_token}

        {:ok, %{status: 401}} ->
          {:error, :refresh_token_expired}

        {:error, reason} ->
          Logger.error("Error refreshing KSeF session: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def get_auth_status(reference_number, auth_token) do
    request()
    |> retry_request()
    |> Req.get(
      url: "/auth/#{reference_number}",
      auth: {:bearer, auth_token},
      retry: fn
        # status code 100 means "in progress"
        _req, res -> match?(%Req.Response{status: 200, body: %{"status" => %{"code" => 100}}}, res)
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

    case Req.post(request(),
           url: "/invoices/exports",
           auth: {:bearer, access_token},
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
    request()
    |> Req.get(
      url: "/invoices/exports/#{reference_number}",
      auth: {:bearer, access_token}
    )
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

  # Moves retry step to the end of the response steps in order
  # to have access to decoded response body in the retry function.
  defp retry_request(request) do
    Req.Request.append_response_steps(
      %{request | response_steps: Enum.reject(request.response_steps, &match?({:retry, _}, &1))},
      retry: &Req.Steps.retry/1
    )
  end
end
