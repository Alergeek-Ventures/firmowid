defmodule FirmowidWeb.WebhookAuth do
  @moduledoc """
  Plug for verifying Svix webhook signatures.

  Implements the Svix webhook signature verification scheme:
  https://docs.svix.com/receiving/verifying-payloads/how

  No official Elixir library exists, so we maintain this implementation.
  """

  import Plug.Conn

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
        Logger.warning("Webhook verification failed: #{inspect(reason)}")
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

  defp get_raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        {:ok, body}

      body ->
        {:ok, body}
    end
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
    signed_content = "#{headers.id}.#{headers.timestamp}.#{body}"
    expected = :hmac |> :crypto.mac(:sha256, secret, signed_content) |> Base.encode64()

    headers.signature
    |> String.split(" ")
    |> Enum.map(fn sig ->
      # Strip version prefix (e.g., "v1,") from signature
      case String.split(sig, ",", parts: 2) do
        [_version, actual_sig] -> actual_sig
        _ -> sig
      end
    end)
    |> Enum.any?(&Plug.Crypto.secure_compare(&1, expected))
    |> case do
      true -> :ok
      false -> {:error, :signature_mismatch}
    end
  end
end
