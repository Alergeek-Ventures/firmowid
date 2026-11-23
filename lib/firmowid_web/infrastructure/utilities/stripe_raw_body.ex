defmodule FirmowidWeb.Infrastructure.Utilities.StripeRawBody do
  @moduledoc """
  `Plug.Parsers` body reader that keeps the raw request body of Stripe events in
  `conn.private.raw_body`, because their signature covers the exact bytes Stripe sent.
  Every other request is read as usual and keeps no copy.
  """

  @doc "Reads the body like `Plug.Conn.read_body/2`, keeping it for `/webhooks/stripe`."
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(%Plug.Conn{path_info: ["webhooks", "stripe"]} = conn, opts) do
    # The JSON parser reads once and reject `:more` as too large, so one read holds the whole body.
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      {:ok, body, Plug.Conn.put_private(conn, :raw_body, body)}
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)
end
