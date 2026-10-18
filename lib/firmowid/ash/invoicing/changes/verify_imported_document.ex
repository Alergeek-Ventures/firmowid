defmodule Firmowid.Ash.Invoicing.Changes.VerifyImportedDocument do
  @moduledoc """
  Rejects an imported invoice whose saved state does not reproduce the KSeF document.

  Firmowid recalculates totals from line net values and keeps a correction's complete
  state after it. Once the import is saved, its gross total (for a correction, the change
  from the state before it) must round to the document's `P_15`, and a correction must
  list every line of that earlier state. Otherwise the error rolls the import back.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidArgument

  @doc "Compares the saved invoice with the `ksef_gross_total` and `corrected_line_count` arguments."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, invoice ->
      opts = Ash.Context.to_opts(context)
      invoice = Ash.load!(invoice, [:gross_value, :reference_invoice], opts)

      reference =
        invoice.reference_invoice &&
          Ash.load!(invoice.reference_invoice, [:gross_value, :sales_invoice_items], opts)

      line_count = Ash.Changeset.get_argument(changeset, :corrected_line_count)
      gross_total = Ash.Changeset.get_argument(changeset, :ksef_gross_total)

      with :ok <- check_lines(reference, line_count),
           :ok <- check_total(invoice, reference, gross_total) do
        {:ok, invoice}
      end
    end)
  end

  defp check_lines(nil, _line_count), do: :ok

  defp check_lines(reference, line_count) do
    if length(reference.sales_invoice_items) == line_count,
      do: :ok,
      else: error(:corrected_line_count, "korekta wykazuje tylko część pozycji faktury korygowanej")
  end

  defp check_total(invoice, reference, gross_total) do
    before = if reference, do: reference.gross_value, else: 0
    gross_change = Decimal.round(Decimal.sub(invoice.gross_value, before), 2)

    if Decimal.equal?(gross_change, gross_total),
      do: :ok,
      else: error(:ksef_gross_total, "kwota brutto po przeliczeniu różni się od faktury w KSeF")
  end

  defp error(field, message), do: {:error, InvalidArgument.exception(field: field, message: message)}
end
