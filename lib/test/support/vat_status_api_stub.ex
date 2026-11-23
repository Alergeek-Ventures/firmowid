defmodule Firmowid.Test.Support.VatStatusApiStub do
  @moduledoc """
  Test-only Req plug standing in for the VAT white list status API (WL2), so the
  NIP check run on every saved Polish counterparty never depends on the network.

  Synthetic NIPs decide the answer: the listed ones are exempt, removed from or
  missing from the VAT register, any other NIP is an active VAT payer.
  """

  @behaviour Plug

  @codes %{"1234563218" => "Z", "1111111111" => "B", "2222222222" => "N", "3333333333" => "N"}

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nip = List.last(conn.path_info)

    Req.Test.json(conn, %{
      "result" => %{"subject" => %{"nip" => nip, "statusCode" => Map.get(@codes, nip, "C")}}
    })
  end
end
