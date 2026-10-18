defmodule Firmowid.Ash.Invoicing.Changes.VerifyImportedDocument do
  @moduledoc """
  Rejects an imported invoice whose saved state does not reproduce the KSeF document.

  Firmowid recalculates totals from line net values, keeps a correction's complete
  state after it and converts a foreign-currency invoice's VAT at its own NBP rate.
  Once the import is saved, its gross total (for a correction, the change from the
  state before it) must round to the document's `P_15`, the document must convert its
  VAT to PLN (`P_14_xW`, `KursWaluty`) at that NBP rate, and a correction must list
  every line of that earlier state.
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
      invoice = Ash.load!(invoice, [:gross_value, :reference_invoice], opts)

      reference =
        invoice.reference_invoice &&
          Ash.load!(
            invoice.reference_invoice,
            [:gross_value, sales_invoice_items: [:vat_value]],
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
  # A PLN document has nothing to convert.
  defp check_vat_pln(%{currency: "PLN"}, _reference, _conversion), do: :ok

  # The document must convert at the NBP rate Firmowid shows: each P_14_xW is its rate's VAT
  # at that rate, and any rate stated on a line is that rate.
  defp check_vat_pln(invoice, reference, %{amounts: amounts, rates: rates}) do
    case Invoicing.get_currency_rate(invoice) do
      nil ->
        raise "NBP exchange rate unavailable for #{invoice.currency} on #{invoice.issue_date}"

      %{rate: rate} ->
        rate = Decimal.from_float(rate)

        converted? =
          Enum.all?(amounts, &Decimal.equal?(vat_pln(&1, reference, rate), &1.vat_pln)) and
            Enum.all?(rates, &Decimal.equal?(&1, rate))

        if converted?,
          do: :ok,
          else: error(:ksef_vat_pln, "faktura w KSeF przelicza VAT na PLN po innym kursie niż NBP")
    end
  end

  defp vat_pln(%{vat: vat}, nil, rate), do: to_pln(vat, rate)

  # A correction's P_14_xW is the difference between the converted states after and before it.
  defp vat_pln(%{vat: change, rates: rates}, reference, rate) do
    before =
      reference.sales_invoice_items
      |> Enum.filter(&(&1.vat_rate in rates))
      |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.vat_value, &2))
      |> Decimal.round(2)

    Decimal.sub(to_pln(Decimal.add(before, change), rate), to_pln(before, rate))
  end

  defp to_pln(vat, rate), do: vat |> Decimal.mult(rate) |> Decimal.round(2)

  defp difference(invoice, nil, field), do: Map.fetch!(invoice, field)

  defp difference(invoice, reference, field), do: Decimal.sub(Map.fetch!(invoice, field), Map.fetch!(reference, field))

  defp error(field, message), do: {:error, InvalidArgument.exception(field: field, message: message)}
end
