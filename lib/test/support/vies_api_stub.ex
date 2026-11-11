defmodule Firmowid.Test.Support.ViesApiStub do
  @moduledoc """
  Test-only Req plug standing in for the EU VIES API, so invoice reviews and the
  periodic counterparty check never depend on the network.

  Synthetic numbers decide the answer: the listed ones are active, numbers starting
  with `000` get the answer VIES gives when a member state's registry does not
  respond, and any other number is inactive.
  """

  @behaviour Plug

  @active ["123456789701", "123456789B01", "123456789"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"vatNumber" => number} = Jason.decode!(body)

    if String.starts_with?(number, "000") do
      Req.Test.json(conn, %{"actionSucceed" => false})
    else
      Req.Test.json(conn, %{"vatNumber" => number, "valid" => number in @active})
    end
  end
end
