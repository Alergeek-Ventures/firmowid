defmodule Firmowid.Test.Support.FakePdfAdapter do
  @moduledoc """
  Test-only adapter for `Firmowid.Invoicing.Services.Pdf` that returns
  an empty binary instead of generating a real PDF through Gotenberg.
  """

  alias Firmowid.Invoicing.SalesInvoice

  @doc false
  @spec generate(SalesInvoice.t(), keyword()) :: {:ok, binary()}
  def generate(_invoice, _opts), do: {:ok, <<>>}
end
