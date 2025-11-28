defmodule Firmowid.Ksef.ApiClient do
  @moduledoc false

  require Logger

  defp request do
    Req.new(
      base_url: Application.fetch_env!(:firmowid, :ksef)[:base_url],
      user_agent: "Firmowid",
      compressed: true
    )
  end

  def parse_timestamp(iso8601) do
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

  defp ksef_public_key do
    Cachex.fetch!(:ksef, :public_key, fn _key ->
      case fetch_and_parse_public_key() do
        {:ok, cert, valid_to} ->
          expire = DateTime.diff(valid_to, DateTime.utc_now(), :millisecond)

          {:commit, cert, expire: expire}

        {:error, reason} ->
          raise "Failed to fetch KSeF public key: #{inspect(reason)}"
      end
    end)
  end

  defp fetch_and_parse_public_key do
    case Req.get(request(), url: "/security/public-key-certificates") do
      {:ok, %{body: certificates}} ->
        result =
          Enum.find_value(certificates, fn
            %{"usage" => ["KsefTokenEncryption"]} = certificate ->
              now = DateTime.utc_now()
              valid_from = parse_timestamp(certificate["validFrom"])
              valid_to = parse_timestamp(certificate["validTo"])

              if DateTime.after?(now, valid_from) and DateTime.before?(now, valid_to) do
                {certificate["certificate"], valid_to}
              end

            _ ->
              nil
          end)

        case result do
          nil ->
            {:error, :no_valid_certificate_found}

          {certificate, valid_to} ->
            certificate =
              certificate
              |> Base.decode64!()
              |> X509.Certificate.from_der!(:Certificate)

            {:ok, certificate, valid_to}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_encrypted_token(ksef_token, timestamp)
       when is_binary(ksef_token) and is_binary(timestamp) do
    pub_key = ksef_public_key()
    timestamp = timestamp |> parse_timestamp() |> DateTime.to_unix(:millisecond)

    "#{ksef_token}|#{timestamp}"
    |> :public_key.encrypt_public(
      X509.Certificate.public_key(pub_key),
      rsa_padding: :rsa_pkcs1_oaep_padding,
      rsa_mgf1_md: :sha256,
      rsa_oaep_md: :sha256
    )
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

    :success = get_auth_status(reference_number, auth_token["token"])

    body =
      Req.post!(request(), url: "/auth/token/redeem", auth: {:bearer, auth_token["token"]}).body

    {:ok,
     %{
       access_token: body["accessToken"]["token"],
       refresh_token: body["refreshToken"]["token"]
     }}
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
    |> Req.get(
      url: "/auth/#{reference_number}",
      auth: {:bearer, auth_token},
      retry: fn
        # status code 100 means "in progress"
        _req, %Req.Response{body: %{"status" => %{"code" => 100}}} -> true
        _, _ -> false
      end
    )
    |> case do
      {:ok, %{body: %{"status" => %{"code" => 200}}}} -> :success
      {:ok, %{body: %{"status" => status}}} -> {:error, status}
      rest -> rest
    end
  end
end
