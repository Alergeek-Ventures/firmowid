defmodule Firmowid.Ash.Invoicing.Services.Pdf do
  @moduledoc """
  Backwards-compatible wrapper for sales invoice PDF generation.
  """

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.SalesInvoicePdf

  @doc """
  Delegates to the configured PDF adapter (defaults to `SalesInvoicePdf`).
  """
  @spec generate(SalesInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%SalesInvoice{} = invoice, opts \\ []) do
    pdf_adapter().generate(invoice, opts)
  end

  defp pdf_adapter do
    Application.get_env(:firmowid, __MODULE__, [])[:adapter] || SalesInvoicePdf
  end
end
