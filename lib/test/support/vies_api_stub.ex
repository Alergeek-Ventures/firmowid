defmodule Firmowid.Test.Support.ViesApiStub do
  @moduledoc """
  Test-only Req plug standing in for the EU VIES API, so invoice reviews with an EU
  buyer never depend on the network. Answers like VIES does when the member state's
  registry does not respond, which the review shows as unavailable.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: Req.Test.json(conn, %{"actionSucceed" => false})
end
