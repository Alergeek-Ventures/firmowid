defmodule Firmowid.Ksef.InvoiceParser do
  @moduledoc """
  Parses FA(3) KSeF invoice XML into a map suitable for CostInvoice changeset.
  """

  import SweetXml

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
    doc = SweetXml.parse(xml)

    issue_date = doc |> xpath(~x"//Fa/P_1/text()"os) |> parse_date()
    # P_6 is sale date - if not present, use issue_date
    sale_date = doc |> xpath(~x"//Fa/P_6/text()"os) |> parse_date() || issue_date
    due_date = doc |> xpath(~x"//Fa/Platnosc/TerminPlatnosci/Termin/text()"os) |> parse_date() || issue_date

    attrs =
      reject_nil_and_empty_values(%{
        # Seller info (Podmiot1)
        seller_nip: xpath(doc, ~x"//Podmiot1/DaneIdentyfikacyjne/NIP/text()"os),
        seller: xpath(doc, ~x"//Podmiot1/DaneIdentyfikacyjne/Nazwa/text()"os),
        seller_display_name: xpath(doc, ~x"//Podmiot1/DaneIdentyfikacyjne/Nazwa/text()"os),
        seller_country_code: xpath(doc, ~x"//Podmiot1/Adres/KodKraju/text()"os),
        seller_address: xpath(doc, ~x"//Podmiot1/Adres/AdresL1/text()"os),
        seller_email: xpath(doc, ~x"//Podmiot1/DaneKontaktowe/Email/text()"os),
        seller_phone: xpath(doc, ~x"//Podmiot1/DaneKontaktowe/Telefon/text()"os),

        # Invoice data (Fa)
        currency: xpath(doc, ~x"//Fa/KodWaluty/text()"os),
        issue_date: issue_date,
        sale_date: sale_date,
        invoice_identifier: xpath(doc, ~x"//Fa/P_2/text()"os),
        total_amount: doc |> xpath(~x"//Fa/P_15/text()"os) |> parse_decimal(),
        invoice_type: doc |> xpath(~x"//Fa/RodzajFaktury/text()"os) |> parse_invoice_type(),

        # For correction invoices (KOR, KOR_ZAL, KOR_ROZ), extract the original invoice's KSeF number
        original_invoice_number: xpath(doc, ~x"//Fa/DaneFaKorygowanej/NrKSeFFaKorygowanej/text()"os),

        # Payment data (Platnosc)
        due_date: due_date,
        payment_method: doc |> xpath(~x"//Fa/Platnosc/FormaPlatnosci/text()"os) |> parse_forma_platnosci(),
        account_number: xpath(doc, ~x"//Fa/Platnosc/RachunekBankowy/NrRB/text()"os),
        items_list:
          xpath(
            doc,
            ~x"//Fa/FaWiersz"l,
            name: ~x"./P_7/text()"os,
            quantity: ~x"./P_8B/text()"of,
            price: ~x"./P_9A/text()"of
          )
      })

    {:ok, attrs}
  rescue
    e -> {:error, e}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
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

  defp reject_nil_and_empty_values(%{} = map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) or v == "" end)
  end
end
