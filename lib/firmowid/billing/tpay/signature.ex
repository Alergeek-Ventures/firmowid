defmodule Firmowid.Billing.Tpay.Signature do
  @moduledoc """
  Verifies the detached JWS (RFC 7515) that Tpay sends in the `X-JWS-Signature`
  header of every notification, as described in https://docs-api.tpay.com/en/webhooks/.

  The header value is `protected..signature`: the payload is the raw request
  body, so the signed input is `protected <> "." <> base64url(raw_body)`. The
  protected header names the signing certificate in `x5u`, which must be served
  by the configured Tpay host. The certificate is checked against Tpay's CA
  bundle from the same host (`/x509/tpay-jws-root.pem`: the intermediate CA,
  then the self-signed root), and its RSA key verifies the RS256 signature.
  Certificates are downloaded on every call; notifications are rare.
  """

  @doc """
  Returns `:ok` when `jws` is a valid Tpay signature of `raw_body`.

  A malformed or forged signature, a certificate outside the configured Tpay
  host or one that Tpay's CA did not issue returns `{:error, :invalid_signature}`.
  A certificate path that does not serve the expected certificates (4xx, a
  redirect, not PEM, a wrong count) is an invalid signature too. Only a Tpay
  outage (transport error or 5xx) raises, so the notification is answered with
  an error and Tpay sends it again.
  """
  @spec verify(binary(), String.t()) :: :ok | {:error, :invalid_signature}
  def verify(raw_body, jws) when is_binary(raw_body) and is_binary(jws) do
    jws_host = Application.fetch_env!(:firmowid, :tpay)[:jws_host]

    with [protected, "", encoded_signature] <- String.split(jws, "."),
         {:ok, %{"alg" => "RS256", "x5u" => x5u}} when is_binary(x5u) <- decode_header(protected),
         %URI{scheme: "https", host: ^jws_host, port: 443, userinfo: nil} <- URI.parse(x5u),
         {:ok, signature} <- Base.url_decode64(encoded_signature, padding: false),
         {:ok, public_key} <- validated_public_key(x5u, jws_host),
         signing_input = protected <> "." <> Base.url_encode64(raw_body, padding: false),
         true <- :public_key.verify(signing_input, :sha256, signature, public_key) do
      :ok
    else
      _invalid -> {:error, :invalid_signature}
    end
  end

  defp decode_header(protected) do
    with {:ok, json} <- Base.url_decode64(protected, padding: false) do
      Jason.decode(json)
    end
  end

  # Tpay's CA bundle and the certificate file list certificates from the signer towards the root,
  # so the reversed list starts with the trust anchor and ends with the signing certificate.
  defp validated_public_key(x5u, jws_host) do
    with {:ok, [signing_certificate]} <- download_certificates(x5u),
         {:ok, [_intermediate, _root | _rest] = bundle} <-
           download_certificates("https://#{jws_host}/x509/tpay-jws-root.pem") do
      [root | intermediates] = Enum.reverse(bundle)

      case :public_key.pkix_path_validation(root, intermediates ++ [signing_certificate], []) do
        {:ok, {{_algorithm, public_key, _params}, _policy_tree}} -> {:ok, public_key}
        {:error, {:bad_cert, _reason}} = error -> error
      end
    else
      {:ok, _wrong_count} -> {:error, :invalid_signature}
      {:error, :invalid_signature} = error -> error
    end
  end

  # A 5xx answer or a transport error raises: Tpay is down, so the notification fails and Tpay
  # sends it again. A 4xx or a redirect means the path serves no certificate.
  defp download_certificates(url) do
    config = Application.fetch_env!(:firmowid, :tpay)

    response =
      [user_agent: "Firmowid", redirect: false, decode_body: false]
      |> Req.new()
      |> Req.merge(config[:request_options] || [])
      |> Req.get!(url: url)

    case response do
      %{status: status} when status >= 500 ->
        raise "Tpay certificate download failed with HTTP #{status}: #{url}"

      %{status: 200, body: pem} ->
        {:ok, for({:Certificate, der, :not_encrypted} <- :public_key.pem_decode(pem), do: der)}

      _other ->
        {:error, :invalid_signature}
    end
  end
end
