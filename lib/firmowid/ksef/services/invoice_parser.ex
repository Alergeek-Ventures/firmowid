defmodule Firmowid.Ksef.Services.InvoiceParser do
  @moduledoc """
  Parses FA(3) KSeF invoice XML into a map suitable for CostInvoice changeset.
  """

  import SweetXml

  @fa3_namespace "http://crd.gov.pl/wzor/2025/06/25/13775/"

  @doc """
  Parses FA(3) XML binary and returns a map of invoice attributes.

  Returns `{:ok, attrs}` on success, `{:error, reason}` on failure.

  ## Example

      iex> xml = File.read!("path/to/invoice.xml")
      iex> {:ok, attrs} = Firmowid.Ksef.Services.InvoiceParser.parse(xml)
      iex> attrs.seller_nip
      "7191575524"
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    attrs =
      xml
      |> SweetXml.parse(namespace_conformant: true, dtd: :none)
      |> xmap(
        seller_nip: tns_xpath(~x"/Faktura/Podmiot1/DaneIdentyfikacyjne/NIP/text()"os),
        seller: tns_xpath(~x"/Faktura/Podmiot1/DaneIdentyfikacyjne/Nazwa/text()"os),
        seller_country_code: tns_xpath(~x"/Faktura/Podmiot1/Adres/KodKraju/text()"os),
        seller_address: tns_xpath(~x"/Faktura/Podmiot1/Adres/AdresL1/text()"os),
        seller_email: tns_xpath(~x"/Faktura/Podmiot1/DaneKontaktowe/Email/text()"os),
        seller_phone: tns_xpath(~x"/Faktura/Podmiot1/DaneKontaktowe/Telefon/text()"os),
        currency: tns_xpath(~x"/Faktura/Fa/KodWaluty/text()"s),
        issue_date: tns_xpath(~x"/Faktura/Fa/P_1/text()"s),
        sale_date: tns_xpath(~x"/Faktura/Fa/P_6/text()"os),
        invoice_identifier: tns_xpath(~x"/Faktura/Fa/P_2/text()"s),
        total_amount: tns_xpath(~x"/Faktura/Fa/P_15/text()"s),
        vat: [
          tns_xpath(~x"/Faktura/Fa"),
          amounts: tns_xpath(~x"./P_14_1/text() | ./P_14_2/text() | ./P_14_3/text() | ./P_14_4/text()"ls),
          amounts_pln: tns_xpath(~x"./P_14_1W/text() | ./P_14_2W/text() | ./P_14_3W/text() | ./P_14_4W/text()"ls)
        ],
        charges: [
          tns_xpath(~x"/Faktura/Fa/Rozliczenie/Obciazenia"l),
          amount: tns_xpath(~x"./Kwota/text()"s)
        ],
        deductions: [
          tns_xpath(~x"/Faktura/Fa/Rozliczenie/Odliczenia"l),
          amount: tns_xpath(~x"./Kwota/text()"s)
        ],
        invoice_type: tns_xpath(~x"/Faktura/Fa/RodzajFaktury/text()"s),
        original_invoice_ksef_number: tns_xpath(~x"/Faktura/Fa/DaneFaKorygowanej/NrKSeFFaKorygowanej/text()"os),
        due_date: tns_xpath(~x"/Faktura/Fa/Platnosc/TerminPlatnosci/Termin/text()"os),
        payment_method: tns_xpath(~x"/Faktura/Fa/Platnosc/FormaPlatnosci/text()"os),
        account_number: tns_xpath(~x"/Faktura/Fa/Platnosc/RachunekBankowy/NrRB/text()"os),
        items_list: [
          tns_xpath(~x"/Faktura/Fa/FaWiersz"l),
          name: tns_xpath(~x"./P_7/text()"os),
          quantity: tns_xpath(~x"./P_8B/text()"of),
          price: tns_xpath(~x"./P_9A/text()"of)
        ],
        order_items: [
          tns_xpath(~x"/Faktura/Fa/Zamowienie/ZamowienieWiersz"l),
          name: tns_xpath(~x"./P_7Z/text()"os),
          quantity: tns_xpath(~x"./P_8BZ/text()"of),
          price: tns_xpath(~x"./P_9AZ/text()"of)
        ]
      )
      |> trim_fields()
      |> Map.update!(:issue_date, &parse_date/1)
      |> Map.update!(:sale_date, &parse_date/1)
      |> Map.update!(:due_date, &parse_date/1)
      |> Map.update!(:total_amount, &parse_decimal/1)
      |> Map.update!(:invoice_type, &parse_invoice_type/1)
      |> Map.update!(:payment_method, &parse_payment_method/1)

    attrs =
      attrs
      |> Map.update!(:sale_date, fn
        nil -> attrs.issue_date
        date -> date
      end)
      |> put_due_date()
      |> put_vat_amount()
      |> put_amount()
      |> put_order_items()

    {:ok, attrs}
  rescue
    e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp tns_xpath(xpath), do: add_namespace(xpath, "", @fa3_namespace)

  defp parse_date(nil), do: nil
  defp parse_date(date), do: Date.from_iso8601!(date)

  defp parse_decimal(nil), do: nil
  defp parse_decimal(amount), do: Decimal.new(amount)

  # A correction states only what it changes (art. 106j ust. 2 pkt 6 of the VAT Act): without
  # TerminPlatnosci the term of the corrected invoice stands, so the correction gets none and
  # `CostInvoice.effective_due_date` keeps the earlier one. An invoice of its own is due on issue.
  defp put_due_date(%{due_date: nil, original_invoice_ksef_number: nil} = attrs),
    do: %{attrs | due_date: attrs.issue_date}

  defp put_due_date(attrs), do: attrs

  # Polish VAT is P_14_1 to P_14_4, which a foreign-currency invoice also states in PLN (P_14_xW);
  # P_14_5 is the VAT of another EU country (OSS). A correction states the change. No field, no VAT.
  defp put_vat_amount(%{vat: vat, currency: currency} = attrs) do
    amounts = if currency == "PLN", do: vat.amounts, else: vat.amounts_pln

    attrs
    |> Map.delete(:vat)
    |> Map.put(
      :vat_amount,
      Enum.reduce(amounts, Decimal.new(0), &Decimal.add(Decimal.new(String.trim(&1)), &2))
    )
  end

  # The amount due is P_15 plus charges (such as a bottle deposit) and minus deductions (Rozliczenie).
  defp put_amount(%{currency: currency, total_amount: total_amount} = attrs) do
    amount_due =
      total_amount
      |> Decimal.add(sum_amounts(attrs.charges))
      |> Decimal.sub(sum_amounts(attrs.deductions))

    attrs
    |> Map.drop([:currency, :total_amount, :charges, :deductions])
    |> Map.put(:amount, Money.new!(currency, amount_due))
  end

  # An advance invoice lists what was ordered in Zamowienie and has no invoice rows.
  defp put_order_items(%{items_list: [], order_items: order_items} = attrs),
    do: attrs |> Map.delete(:order_items) |> Map.put(:items_list, order_items)

  defp put_order_items(attrs), do: Map.delete(attrs, :order_items)

  defp sum_amounts(entries), do: Enum.reduce(entries, Decimal.new(0), &Decimal.add(Decimal.new(&1.amount), &2))

  defp parse_invoice_type("VAT"), do: :vat
  defp parse_invoice_type("KOR"), do: :kor
  defp parse_invoice_type("ZAL"), do: :zal
  defp parse_invoice_type("ROZ"), do: :roz
  defp parse_invoice_type("UPR"), do: :upr
  defp parse_invoice_type("KOR_ZAL"), do: :kor_zal
  defp parse_invoice_type("KOR_ROZ"), do: :kor_roz

  defp parse_invoice_type(type) do
    raise ArgumentError, "Unknown FA(3) invoice type: #{inspect(type)}"
  end

  defp parse_payment_method(nil), do: nil
  defp parse_payment_method("1"), do: :cash
  defp parse_payment_method("2"), do: :card
  defp parse_payment_method("3"), do: :voucher
  defp parse_payment_method("4"), do: :check
  defp parse_payment_method("5"), do: :loan
  defp parse_payment_method("6"), do: :bank_transfer
  defp parse_payment_method("7"), do: :mobile

  defp parse_payment_method(code) do
    raise ArgumentError, "Unknown FA(3) payment method code: #{inspect(code)}"
  end

  defp trim_fields(map) do
    Map.new(map, fn
      {k, ""} ->
        {k, nil}

      {k, v} when is_binary(v) ->
        case String.trim(v) do
          "" -> {k, nil}
          trimmed -> {k, trimmed}
        end

      {k, v} when is_list(v) ->
        {k, Enum.map(v, &trim_fields/1)}

      {k, v} ->
        {k, v}
    end)
  end
end
