defmodule Firmowid.Ash.Invoicing.Services.SalesInvoicePdf do
  @moduledoc """
  Orchestrates sales-invoice PDF generation.

  The pipeline is:

    base PDF -> optional augmentations -> final PDF
  """

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.PdfAugmentations.InternalNote
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceBasePdf

  require Logger

  @doc """
  Generates a sales-invoice PDF with optional augmentations.
  """
  @spec generate(SalesInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%SalesInvoice{} = invoice, opts \\ []) do
    include_internal_note = Keyword.get(opts, :include_internal_note, false)
    invoice = maybe_load_internal_note(invoice, opts, include_internal_note)
    internal_note = if include_internal_note, do: invoice.internal_note

    with {:ok, base_pdf} <- SalesInvoiceBasePdf.generate(invoice, opts),
         {:ok, final_pdf} <-
           InternalNote.maybe_insert(base_pdf, internal_note, include_internal_note) do
      {:ok, final_pdf}
    else
      {:error, reason} = error ->
        Logger.error("Sales invoice PDF generation failed for #{invoice.id}: #{inspect(reason)}")
        error
    end
  end

  defp maybe_load_internal_note(invoice, _opts, false), do: invoice

  defp maybe_load_internal_note(invoice, opts, true) do
    case Keyword.get(opts, :scope) do
      nil -> Ash.load!(invoice, [:internal_note], tenant: invoice.organization_id)
      scope -> Ash.load!(invoice, [:internal_note], scope: scope)
    end
  end
end
