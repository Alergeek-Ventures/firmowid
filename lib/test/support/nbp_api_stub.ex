defmodule Firmowid.Test.Support.NbpApiStub do
  @moduledoc """
  Test-only Req plug standing in for the NBP exchange-rate API, so rendering
  foreign-currency invoices in tests never depends on the network. Returns one
  fixed rate effective on the last day of the requested range.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: [_, _, _, _, currency, _start_date, end_date]} = conn, _opts) do
    Req.Test.json(conn, %{
      "code" => currency,
      "rates" => [%{"no" => "001/A/NBP/TEST", "effectiveDate" => end_date, "mid" => 4.0}]
    })
  end
end
