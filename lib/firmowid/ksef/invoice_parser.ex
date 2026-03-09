defmodule Firmowid.Ksef.InvoiceParser do
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
      iex> {:ok, attrs} = Firmowid.Ksef.InvoiceParser.parse(xml)
      iex> attrs.seller_nip
      "7191575524"
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    doc =
      SweetXml.parse(xml,
        namespace_conformant: true
        # todo: add xsd validation
        # validation: :schema,
        # schemaLocation: [tns: "http://crd.gov.pl/wzor/2025/06/25/13775/"]
      )

    issue_date = doc |> xpath(tns_xpath(~x"//tns:Fa/tns:P_1/text()"s)) |> parse_date()
    # P_6 is sale date - if not present, use issue_date
    sale_date = doc |> xpath(tns_xpath(~x"//tns:Fa/tns:P_6/text()"os)) |> parse_date() || issue_date

    due_date =
      doc
      |> xpath(tns_xpath(~x"//tns:Fa/tns:Platnosc/tns:TerminPlatnosci/tns:Termin/text()"os))
      |> parse_date() ||
        issue_date

    attrs =
      %{
        # Seller info (Podmiot1)
        seller_nip: xpath(doc, tns_xpath(~x"//tns:Podmiot1/tns:DaneIdentyfikacyjne/tns:NIP/text()"os)),
        seller: xpath(doc, tns_xpath(~x"//tns:Podmiot1/tns:DaneIdentyfikacyjne/tns:Nazwa/text()"os)),
        seller_display_name: xpath(doc, tns_xpath(~x"//tns:Podmiot1/tns:DaneIdentyfikacyjne/tns:Nazwa/text()"os)),
        seller_country_code: xpath(doc, tns_xpath(~x"//tns:Podmiot1/tns:Adres/tns:KodKraju/text()"os)),
        seller_address: xpath(doc, tns_xpath(~x"//tns:Podmiot1/tns:Adres/tns:AdresL1/text()"os)),
        seller_email: xpath(doc, tns_xpath(~x"//tns:Podmiot1/tns:DaneKontaktowe/tns:Email/text()"os)),
        seller_phone: xpath(doc, tns_xpath(~x"//tns:Podmiot1/tns:DaneKontaktowe/tns:Telefon/text()"os)),

        # Invoice data (Fa)
        currency: xpath(doc, tns_xpath(~x"//tns:Fa/tns:KodWaluty/text()"s)),
        issue_date: issue_date,
        sale_date: sale_date,
        invoice_identifier: xpath(doc, tns_xpath(~x"//tns:Fa/tns:P_2/text()"s)),
        total_amount: xpath(doc, tns_xpath(~x"//tns:Fa/tns:P_15/text()"s)),
        invoice_type: xpath(doc, tns_xpath(~x"//tns:Fa/tns:RodzajFaktury/text()"s)),

        # For correction invoices (KOR, KOR_ZAL, KOR_ROZ), extract the original invoice's KSeF number
        original_invoice_number:
          xpath(doc, tns_xpath(~x"//tns:Fa/tns:DaneFaKorygowanej/tns:NrKSeFFaKorygowanej/text()"os)),

        # Payment data (Platnosc)
        due_date: due_date,
        payment_method: xpath(doc, tns_xpath(~x"//tns:Fa/tns:Platnosc/tns:FormaPlatnosci/text()"os)),
        account_number: xpath(doc, tns_xpath(~x"//tns:Fa/tns:Platnosc/tns:RachunekBankowy/tns:NrRB/text()"os)),
        items_list:
          xpath(
            doc,
            tns_xpath(~x"//tns:Fa/tns:FaWiersz"l),
            name: tns_xpath(~x"./tns:P_7/text()"os),
            quantity: tns_xpath(~x"./tns:P_8B/text()"of),
            price: tns_xpath(~x"./tns:P_9A/text()"of)
          )
      }
      |> trim_values()
      |> Map.update!(:total_amount, &parse_decimal/1)
      |> Map.update!(:invoice_type, &parse_invoice_type/1)
      |> Map.update!(:payment_method, &parse_forma_platnosci/1)
      |> reject_nil_and_empty_values()

    {:ok, attrs}
  rescue
    e -> {:error, e}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    date_string
    |> String.trim()
    |> Date.from_iso8601()
    |> case do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_decimal(amount_string) do
    case Decimal.parse(amount_string) do
      {decimal, ""} -> decimal
      _ -> raise "Invalid decimal format: #{amount_string}"
    end
  end

  defp parse_invoice_type(type_string) do
    case type_string do
      "VAT" -> :vat
      "KOR" -> :kor
      "ZAL" -> :zal
      "ROZ" -> :roz
      "UPR" -> :upr
      "KOR_ZAL" -> :kor_zal
      "KOR_ROZ" -> :kor_roz
      _ -> raise "Unknown invoice type: #{type_string}"
    end
  end

  defp parse_forma_platnosci(code) do
    case code do
      "1" -> :cash
      "2" -> :card
      "3" -> :voucher
      "4" -> :check
      "5" -> :loan
      "6" -> :bank_transfer
      "7" -> :mobile
      _ -> nil
    end
  end

  defp tns_xpath(xpath) do
    add_namespace(xpath, "tns", @fa3_namespace)
  end

  defp trim_values(%{} = map) do
    Map.new(map, fn
      {k, v} when is_binary(v) -> {k, String.trim(v)}
      {k, v} when is_list(v) -> {k, Enum.map(v, &trim_values/1)}
      {k, v} -> {k, v}
    end)
  end

  defp reject_nil_and_empty_values(%{} = map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) or v == "" end)
  end
end
