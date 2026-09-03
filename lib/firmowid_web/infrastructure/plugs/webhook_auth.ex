defmodule FirmowidWeb.Infrastructure.Plugs.WebhookAuth do
  @moduledoc """
  Plug for verifying Svix webhook signatures.

  Implements the Svix webhook signature verification scheme:
  https://docs.svix.com/receiving/verifying-payloads/how

  No official Elixir library exists, so we maintain this implementation.

  ## Verification Steps

  1. Extract required headers (svix-id, svix-timestamp, svix-signature)
  2. Verify timestamp is within acceptable window (5 minutes)
  3. Decode the webhook secret (strip `whsec_` prefix and base64-decode)
  4. Compute HMAC-SHA256 signature of `{id}.{timestamp}.{body}`
  5. Compare computed signature with provided signature(s) using constant-time comparison
  """

  import Plug.Conn

  alias Firmowid.ErrorKind

  require Logger

  @five_minutes_in_seconds 300

  def init(opts), do: opts

  def call(conn, _opts) do
    secret = Application.fetch_env!(:firmowid, :resend_webhook_secret)

    with {:ok, headers} <- extract_headers(conn),
         {:ok, body} <- get_raw_body(conn),
         :ok <- verify_timestamp(headers.timestamp),
         :ok <- verify_signature(secret, headers, body) do
      assign(conn, :raw_body, body)
    else
      {:error, reason} ->
        Logger.warning("Webhook verification failed",
          error_kind: ErrorKind.classify(reason)
        )

        conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end

  defp extract_headers(conn) do
    with {:ok, id} <- get_header(conn, "svix-id"),
         {:ok, timestamp} <- get_header(conn, "svix-timestamp"),
         {:ok, signature} <- get_header(conn, "svix-signature") do
      {:ok, %{id: id, timestamp: timestamp, signature: signature}}
    end
  end

  defp get_header(conn, name) do
    case get_req_header(conn, name) do
      [value] -> {:ok, value}
      [] -> {:error, {:missing_header, name}}
      _ -> {:error, {:duplicate_header, name}}
    end
  end

  defp get_raw_body(%{private: %{raw_body: body}}), do: {:ok, body}

  defp get_raw_body(conn) do
    {:ok, body, _conn} = read_body(conn)
    {:ok, body}
  end

  defp verify_timestamp(timestamp_str) do
    with {timestamp, ""} <- Integer.parse(timestamp_str),
         age = System.system_time(:second) - timestamp,
         true <- abs(age) <= @five_minutes_in_seconds do
      :ok
    else
      :error -> {:error, :invalid_timestamp}
      {_, _} -> {:error, :invalid_timestamp}
      false -> {:error, :timestamp_too_old}
    end
  end

  defp verify_signature(secret, headers, body) do
    with {:ok, decoded_secret} <- decode_secret(secret),
         expected = compute_signature(decoded_secret, headers, body),
         provided_signatures = parse_signatures(headers.signature),
         true <- signature_matches?(provided_signatures, expected) do
      :ok
    else
      {:error, _reason} = error -> error
      false -> {:error, :signature_mismatch}
    end
  end

  defp decode_secret("whsec_" <> base64_part) do
    case Base.decode64(base64_part) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_secret_encoding}
    end
  end

  defp decode_secret(_other), do: {:error, :invalid_secret_format}

  defp compute_signature(decoded_secret, headers, body) do
    signed_content = "#{headers.id}.#{headers.timestamp}.#{body}"

    decoded_secret
    |> then(&:crypto.mac(:hmac, :sha256, &1, signed_content))
    |> Base.encode64()
  end

  defp parse_signatures(signature_header) do
    signature_header
    |> String.split(" ")
    |> Enum.map(&strip_version_prefix/1)
  end

  defp strip_version_prefix(signature) do
    case String.split(signature, ",", parts: 2) do
      [_version, actual_sig] -> actual_sig
      _ -> signature
    end
  end

  defp signature_matches?(provided_signatures, expected) do
    Enum.any?(provided_signatures, &Plug.Crypto.secure_compare(&1, expected))
  end
end
