defmodule Firmowid.Ash.Invoicing.Services.CostInvoiceBasePdf.Blob do
  @moduledoc """
  Generates the base PDF for uploaded PDF cost invoices.
  """

  alias Firmowid.Ash.Invoicing.CostInvoice

  @doc """
  Fetches the uploaded PDF blob and returns it as the base PDF.
  """
  @spec generate(CostInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%CostInvoice{} = invoice, opts \\ []) do
    ash_scope = Keyword.get(opts, :scope)

    invoice = Ash.load!(invoice, [blob: [:url]], scope: ash_scope)

    with {:ok, blob_binary} <- load_blob_content(invoice),
         :ok <- validate_pdf_binary(blob_binary) do
      {:ok, blob_binary}
    end
  end

  defp load_blob_content(invoice) do
    case Req.get(invoice.blob.url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:blob_fetch_failed, status}}
      {:error, reason} -> {:error, {:blob_fetch_failed, reason}}
    end
  end

  defp validate_pdf_binary(<<"%PDF-", _rest::binary>>), do: :ok
  defp validate_pdf_binary(_binary), do: {:error, :unsupported_cost_invoice_blob_type}
end
