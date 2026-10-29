defmodule Firmowid.Invoicing.Changes.VerifyImportedDocument do
  @moduledoc """
  Rejects an imported invoice whose saved state does not reproduce the KSeF document.

  Firmowid recalculates totals from line net values, keeps a correction's complete
  state after it and converts a foreign-currency invoice's VAT at its own NBP rate.
  Once the import is saved, its gross total (for a correction, the change from the
  state before it) must round to the document's `P_15`, each rate group's VAT must match
  its `P_14_x`, a foreign currency must have an NBP rate and the document must convert
  that VAT to PLN (`P_14_xW`, `KursWaluty`) at it, and a correction must list exactly the
  lines of that earlier state.
  Otherwise the error rolls the import back.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidArgument
  alias Firmowid.Currencies.NbpApiClient
  alias Firmowid.Invoicing

  @doc """
  Compares the saved invoice with the `ksef_gross_total`, `ksef_vat` and
  `corrected_lines` arguments.
  """
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, invoice ->
      opts = Ash.Context.to_opts(context)

      invoice =
        Ash.load!(
          invoice,
          [:gross_value, :reference_invoice, sales_invoice_items: [:net_value, :vat_value]],
          opts
        )

      reference =
        invoice.reference_invoice &&
          Ash.load!(
            invoice.reference_invoice,
            [:gross_value, sales_invoice_items: [:net_value, :vat_value]],
            opts
          )

      corrected_lines = Ash.Changeset.get_argument(changeset, :corrected_lines)
      gross_total = Ash.Changeset.get_argument(changeset, :ksef_gross_total)
      vat = Ash.Changeset.get_argument(changeset, :ksef_vat)

      with :ok <- check_lines(reference, corrected_lines),
           :ok <- check_total(invoice, reference, gross_total),
           :ok <- check_vat_groups(invoice, reference, vat),
           :ok <- check_vat_pln(invoice, reference, vat) do
        {:ok, invoice}
      end
    end)
  end

  defp check_lines(nil, _lines), do: :ok

  # The lines a correction lists before it must be the state it corrects in Firmowid.
  defp check_lines(reference, lines) do
    if line_values(reference.sales_invoice_items, & &1.net_value) == line_values(lines, & &1.net),
      do: :ok,
      else:
        error(
          :corrected_lines,
          "pozycje przed korektą różnią się od faktury korygowanej w Firmowidzie"
        )
  end

  defp line_values(lines, net) do
    lines
    |> Enum.map(&{&1 |> net.() |> Decimal.round(2) |> Decimal.to_string(:normal), &1.vat_rate})
    |> Enum.sort()
  end

  defp check_total(invoice, reference, gross_total) do
    if Decimal.equal?(
         Decimal.round(difference(invoice, reference, :gross_value), 2),
         gross_total
       ),
       do: :ok,
       else: error(:ksef_gross_total, "kwota brutto po przeliczeniu różni się od faktury w KSeF")
  end

  # Each P_14_x is its rate group's VAT rounded to the grosz; for a correction, the change
  # between the rounded groups after and before it.
  defp check_vat_groups(invoice, reference, %{groups: groups, net_groups: net_groups}) do
    vat? =
      Enum.all?(
        groups,
        &Decimal.equal?(group_change(invoice, reference, &1.rates, :vat_value), &1.vat)
      )

    net? =
      Enum.all?(
        net_groups,
        &Decimal.equal?(group_change(invoice, reference, &1.rates, :net_value), &1.net)
      )

    if vat? and net?,
      do: :ok,
      else:
        error(
          :ksef_vat,
          "netto lub VAT w grupach stawek po przeliczeniu różni się od faktury w KSeF"
        )
  end

  # A PLN document has nothing to convert. Any other currency needs the NBP rate Firmowid
  # shows on the PDF, and the document must convert at it: each P_14_xW is its group's VAT
  # at that rate, and any rate stated on a line is that rate.
  defp check_vat_pln(%{currency: "PLN"}, _reference, _vat), do: :ok

  defp check_vat_pln(invoice, reference, %{groups: groups, line_rates: line_rates}) do
    date = Invoicing.get_currency_conversion_date(invoice.issue_date, invoice.sale_date)

    case NbpApiClient.get_exchange_rate(invoice.currency, date) do
      {:ok, %{rate: rate}} ->
        rate = Decimal.from_float(rate)

        converted? =
          Enum.all?(
            groups,
            &(is_nil(&1.vat_pln) or
                Decimal.equal?(group_pln(invoice, reference, &1.rates, rate), &1.vat_pln))
          ) and
            Enum.all?(line_rates, &Decimal.equal?(&1, rate))

        if converted?,
          do: :ok,
          else: error(:ksef_vat, "faktura w KSeF przelicza VAT na PLN po innym kursie niż NBP")

      # NBP's table A has no rate for this currency, so Firmowid cannot show its conversion.
      {:error, {:no_rates_found, _currency, _date}} ->
        error(:ksef_vat, "NBP nie publikuje kursu waluty #{invoice.currency}")

      {:error, reason} ->
        raise "NBP exchange rate unavailable for #{invoice.currency} on #{date}: #{inspect(reason)}"
    end
  end

  defp group_change(invoice, nil, rates, field), do: group_sum(invoice, rates, field)

  defp group_change(invoice, reference, rates, field),
    do: Decimal.sub(group_sum(invoice, rates, field), group_sum(reference, rates, field))

  # A correction's P_14_xW is the difference between the converted states after and before it.
  defp group_pln(invoice, nil, rates, rate), do: to_pln(group_sum(invoice, rates, :vat_value), rate)

  defp group_pln(invoice, reference, rates, rate),
    do:
      Decimal.sub(
        to_pln(group_sum(invoice, rates, :vat_value), rate),
        to_pln(group_sum(reference, rates, :vat_value), rate)
      )

  defp group_sum(invoice, rates, field) do
    invoice.sales_invoice_items
    |> Enum.filter(&(&1.vat_rate in rates))
    |> Enum.reduce(Decimal.new(0), &Decimal.add(Map.fetch!(&1, field), &2))
    |> Decimal.round(2)
  end

  defp to_pln(vat, rate), do: vat |> Decimal.mult(rate) |> Decimal.round(2)

  defp difference(invoice, nil, field), do: Map.fetch!(invoice, field)

  defp difference(invoice, reference, field), do: Decimal.sub(Map.fetch!(invoice, field), Map.fetch!(reference, field))

  defp error(field, message), do: {:error, InvalidArgument.exception(field: field, message: message)}
end
