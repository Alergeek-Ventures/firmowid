defmodule Firmowid.Ash.Invoicing.Changes.VerifyImportedDocument do
  @moduledoc """
  Rejects an imported invoice whose saved state does not reproduce the KSeF document.

  Firmowid recalculates totals from line net values, keeps a correction's complete
  state after it and converts a foreign-currency invoice's VAT at its own NBP rate.
  Once the import is saved, its gross total (for a correction, the change from the
  state before it) must round to the document's `P_15`, its VAT in PLN must match the
  document's `P_14_xW`, and a correction must list every line of that earlier state.
  Otherwise the error rolls the import back.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidArgument
  alias Firmowid.Ash.Invoicing

  @doc """
  Compares the saved invoice with the `ksef_gross_total`, `ksef_vat_pln` and
  `corrected_line_count` arguments.
  """
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, invoice ->
      opts = Ash.Context.to_opts(context)
      invoice = Ash.load!(invoice, [:gross_value, :vat_value, :reference_invoice], opts)

      reference =
        invoice.reference_invoice &&
          Ash.load!(
            invoice.reference_invoice,
            [:gross_value, :vat_value, :sales_invoice_items],
            opts
          )

      line_count = Ash.Changeset.get_argument(changeset, :corrected_line_count)
      gross_total = Ash.Changeset.get_argument(changeset, :ksef_gross_total)
      vat_pln = Ash.Changeset.get_argument(changeset, :ksef_vat_pln)

      with :ok <- check_lines(reference, line_count),
           :ok <- check_total(invoice, reference, gross_total),
           :ok <- check_vat_pln(invoice, reference, vat_pln) do
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
    if Decimal.equal?(
         Decimal.round(difference(invoice, reference, :gross_value), 2),
         gross_total
       ),
       do: :ok,
       else: error(:ksef_gross_total, "kwota brutto po przeliczeniu różni się od faktury w KSeF")
  end

  defp check_vat_pln(_invoice, _reference, nil), do: :ok

  # Each P_14_xW converts that rate's VAT rounded to the grosz and is rounded itself, so per
  # amount they may differ from the converted total by half a grosz times the rate plus a grosz.
  defp check_vat_pln(invoice, reference, %{total: total, count: count}) do
    case Invoicing.get_currency_rate(invoice) do
      nil ->
        raise "NBP exchange rate unavailable for #{invoice.currency} on #{invoice.issue_date}"

      %{rate: rate} ->
        rate = Decimal.from_float(rate)
        vat = Decimal.round(difference(invoice, reference, :vat_value), 2)
        gap = vat |> Decimal.mult(rate) |> Decimal.sub(total) |> Decimal.abs()
        per_amount = Decimal.add(Decimal.new("0.01"), Decimal.mult(Decimal.new("0.005"), rate))

        if Decimal.compare(gap, Decimal.mult(per_amount, count)) == :gt,
          do: error(:ksef_vat_pln, "VAT w PLN po kursie NBP różni się od faktury w KSeF"),
          else: :ok
    end
  end

  defp difference(invoice, nil, field), do: Map.fetch!(invoice, field)

  defp difference(invoice, reference, field), do: Decimal.sub(Map.fetch!(invoice, field), Map.fetch!(reference, field))

  defp error(field, message), do: {:error, InvalidArgument.exception(field: field, message: message)}
end
