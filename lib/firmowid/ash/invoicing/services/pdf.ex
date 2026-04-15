defmodule Firmowid.Ash.Invoicing.Services.Pdf do
  @moduledoc """
  Backwards-compatible wrapper for sales invoice PDF generation.
  """

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.SalesInvoicePdf

  @doc """
  Delegates to `SalesInvoicePdf.generate/2`.
  """
  @spec generate(SalesInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%SalesInvoice{} = invoice, opts \\ []) do
    SalesInvoicePdf.generate(invoice, opts)
  end
end
