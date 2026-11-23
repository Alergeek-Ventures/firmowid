defmodule Firmowid.Test.Support.CeidgApiStub do
  @moduledoc """
  Test-only Req plug standing in for CEIDG, so the NIP check of a counterparty
  outside the VAT register never depends on the network. CEIDG knows none of the
  synthetic NIPs and answers 204, as it does for a NIP without a business.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: Plug.Conn.send_resp(conn, 204, "")
end
