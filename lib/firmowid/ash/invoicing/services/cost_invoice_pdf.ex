defmodule Firmowid.Ash.Invoicing.Services.CostInvoicePdf do
  @moduledoc """
  Orchestrates cost-invoice PDF generation.

  The pipeline is:

    base PDF -> optional augmentations -> final PDF
  """

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.Services.CostInvoiceBasePdf.Blob
  alias Firmowid.Ash.Invoicing.Services.CostInvoiceBasePdf.Ksef
  alias Firmowid.Ash.Invoicing.Services.PdfAugmentations.InternalNote
  alias Firmowid.ErrorKind

  require Logger

  @doc """
  Generates a cost-invoice PDF with optional augmentations.
  """
  @spec generate(CostInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%CostInvoice{} = invoice, opts \\ []) do
    invoice = load_internal_note(invoice, opts)
    include_internal_note = Keyword.get(opts, :include_internal_note, true)

    with {:ok, base_pdf} <- generate_base_pdf(invoice, opts),
         {:ok, final_pdf} <-
           InternalNote.maybe_insert(base_pdf, invoice.internal_note, include_internal_note) do
      {:ok, final_pdf}
    else
      {:error, reason} = error ->
        Logger.error("Cost invoice PDF generation failed",
          invoice_id: invoice.id,
          error_kind: ErrorKind.classify(reason)
        )

        error
    end
  end

  defp generate_base_pdf(%CostInvoice{ksef_number: ksef_number} = invoice, opts) when not is_nil(ksef_number),
    do: Ksef.generate(invoice, opts)

  defp generate_base_pdf(%CostInvoice{} = invoice, opts), do: Blob.generate(invoice, opts)

  defp load_internal_note(invoice, opts) do
    case Keyword.get(opts, :scope) do
      nil -> Ash.load!(invoice, [:internal_note], tenant: invoice.organization_id)
      scope -> Ash.load!(invoice, [:internal_note], scope: scope)
    end
  end
end
