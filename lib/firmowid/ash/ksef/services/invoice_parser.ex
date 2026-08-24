defmodule Firmowid.Ash.Ksef.Services.InvoiceParser do
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
      iex> {:ok, attrs} = Firmowid.Ash.Ksef.Services.InvoiceParser.parse(xml)
      iex> attrs.seller_nip
      "7191575524"
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    attrs =
      xml
      |> SweetXml.parse(namespace_conformant: true)
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
      |> Map.update!(:due_date, fn
        nil -> attrs.issue_date
        date -> date
      end)
      |> put_amount()

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

  defp put_amount(%{currency: currency, total_amount: total_amount} = attrs) do
    attrs
    |> Map.delete(:currency)
    |> Map.delete(:total_amount)
    |> Map.put(:amount, Money.new!(currency, total_amount))
  end

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
