defmodule FirmowidWeb.CacheBodyReader do
  @moduledoc """
  Custom body reader that caches the raw body for webhook signature verification.

  ## Problem

  Phoenix's `Plug.Parsers` consumes the request body stream when parsing JSON,
  making it unavailable for subsequent operations. However, webhook signature
  verification requires the exact raw body to compute HMAC signatures.

  ## Solution

  This module acts as a custom body reader that:
  1. Reads the body once from the stream
  2. Caches it in `conn.private[:raw_body]`
  3. Returns the body to `Plug.Parsers` for normal parsing

  This allows both JSON parsing and signature verification to work correctly.

  ## Usage

  Configure in `endpoint.ex`:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        body_reader: {FirmowidWeb.CacheBodyReader, :read_body, []}
  """

  @doc """
  Reads the request body and caches it in conn.private for later use.

  This function is called by `Plug.Parsers` during the parsing phase.
  """
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    {:ok, body, Plug.Conn.put_private(conn, :raw_body, body)}
  end
end
