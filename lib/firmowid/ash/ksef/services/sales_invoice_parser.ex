defmodule Firmowid.Ash.Ksef.Services.SalesInvoiceParser do
  @moduledoc """
  Parses an FA(3) sales invoice issued outside Firmowid into `SalesInvoice` attributes.

  It reads the elements `InvoiceRenderer` writes. A document the sales invoice cannot
  represent is rejected with `{:error, {:unsupported, reason}}`: invoice kinds other than
  VAT and KOR, gross-only lines, VAT rates outside `VatRate`, and corrections listing
  only differences instead of the state before and after.

  A correction also reports how many lines it lists before the correction, so the
  import can reject one that lists only some lines of the corrected invoice.
  """

  import SweetXml

  alias Firmowid.Ash.Invoicing.VatExemption
  alias Firmowid.Ash.Ksef.VatRate

  @fa3_namespace "http://crd.gov.pl/wzor/2025/06/25/13775/"
  @payment_methods %{
    "1" => :cash,
    "2" => :card,
    "3" => :voucher,
    "4" => :check,
    "5" => :credit,
    "6" => :transfer,
    "7" => :mobile
  }
  @exemption_types Map.new(VatExemption.valid_types(), &{VatExemption.label(&1), &1})
  # FA(3) makes the unit optional, while every Firmowid line has one.
  @default_unit "szt."

  @doc """
  Parses FA(3) XML into attributes for `SalesInvoice.import_from_ksef`, including
  `:sales_invoice_items` and, for a correction, `:corrected_invoice_ksef_number` and
  `:corrected_line_count`.
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, {:unsupported, String.t()} | term()}
  def parse(xml) when is_binary(xml) do
    doc = SweetXml.parse(xml, namespace_conformant: true)

    with {:ok, kind} <- invoice_kind(text(doc, "/Faktura/Fa/RodzajFaktury")),
         {:ok, items, corrected_line_count} <- items(doc, kind),
         {:ok, payment_method} <- payment_method(text(doc, "/Faktura/Fa/Platnosc/FormaPlatnosci")) do
      issue_date = date(text(doc, "/Faktura/Fa/P_1"))

      {:ok,
       doc
       |> seller()
       |> Map.merge(buyer(doc))
       |> Map.merge(exemption(doc))
       |> Map.merge(%{
         ksef_invoice_kind: kind,
         invoice_type: invoice_type(doc),
         invoice_number: text(doc, "/Faktura/Fa/P_2"),
         currency: text(doc, "/Faktura/Fa/KodWaluty"),
         issue_date: issue_date,
         sale_date: date(text(doc, "/Faktura/Fa/P_6")) || issue_date,
         due_date: date(text(doc, "/Faktura/Fa/Platnosc/TerminPlatnosci/Termin")) || issue_date,
         payment_method: payment_method,
         seller_account_number: text(doc, "/Faktura/Fa/Platnosc/RachunekBankowy/NrRB"),
         is_reverse_charge: text(doc, "/Faktura/Fa/Adnotacje/P_18") == "1",
         invoice_note: text(doc, "/Faktura/Stopka/Informacje/StopkaFaktury"),
         correction_reason: text(doc, "/Faktura/Fa/PrzyczynaKorekty"),
         corrected_invoice_ksef_number: text(doc, "/Faktura/Fa/DaneFaKorygowanej/NrKSeFFaKorygowanej"),
         corrected_line_count: corrected_line_count,
         sales_invoice_items: items
       })}
    end
  rescue
    e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp invoice_kind("VAT"), do: {:ok, :vat}
  defp invoice_kind("KOR"), do: {:ok, :kor}
  defp invoice_kind(kind), do: {:error, {:unsupported, "invoice kind #{kind}"}}

  defp seller(doc) do
    %{
      seller_nip: text(doc, "/Faktura/Podmiot1/DaneIdentyfikacyjne/NIP"),
      seller_display_name: text(doc, "/Faktura/Podmiot1/DaneIdentyfikacyjne/Nazwa"),
      seller_address: address(doc, "/Faktura/Podmiot1/Adres")
    }
  end

  # FA(3) holds the buyer's name in one element; a Polish buyer without a tax ID is a consumer.
  defp buyer(doc) do
    id = "/Faktura/Podmiot2/DaneIdentyfikacyjne"
    name = text(doc, "#{id}/Nazwa")
    address_country = text(doc, "/Faktura/Podmiot2/Adres/KodKraju")

    {buyer_id, country} =
      cond do
        nip = text(doc, "#{id}/NIP") -> {nip, address_country || "PL"}
        vat_ue = text(doc, "#{id}/NrVatUE") -> {vat_ue, text(doc, "#{id}/KodUE")}
        nr_id = text(doc, "#{id}/NrID") -> {nr_id, text(doc, "#{id}/KodKraju") || address_country}
        true -> {nil, address_country}
      end

    names =
      if is_nil(buyer_id) and country == "PL" do
        {given_names, [surname]} = name |> String.split() |> Enum.split(-1)

        %{
          buyer_type: :individual,
          buyer_display_name: name,
          buyer_given_name: Enum.join(given_names, " "),
          buyer_surname: surname
        }
      else
        %{buyer_type: :company, buyer_full_name: name}
      end

    Map.merge(names, %{
      buyer_id: buyer_id,
      buyer_country: country,
      buyer_address: address(doc, "/Faktura/Podmiot2/Adres"),
      buyer_email: text(doc, "/Faktura/Podmiot2/DaneKontaktowe/Email"),
      buyer_phone: text(doc, "/Faktura/Podmiot2/DaneKontaktowe/Telefon")
    })
  end

  defp invoice_type(doc) do
    if text(doc, "/Faktura/Podmiot2/Adres/KodKraju") in [nil, "PL"], do: :poland, else: :foreign
  end

  defp exemption(doc) do
    zwolnienie = "/Faktura/Fa/Adnotacje/Zwolnienie"

    cond do
      basis = text(doc, "#{zwolnienie}/P_19A") ->
        case Map.fetch(@exemption_types, basis) do
          {:ok, type} -> %{vat_exemption_type: type}
          :error -> %{vat_exemption_type: :other, vat_exemption_basis: basis}
        end

      text(doc, "#{zwolnienie}/P_19B") ->
        %{vat_exemption_type: :directive_2006_112}

      basis = text(doc, "#{zwolnienie}/P_19C") ->
        %{vat_exemption_type: :other, vat_exemption_basis: basis}

      true ->
        %{}
    end
  end

  # A correction lists the lines before (StanPrzed) and after it; the invoice keeps the latter.
  defp items(doc, kind) do
    rows =
      doc
      |> xpath(tns(~x"/Faktura/Fa/FaWiersz"l))
      |> Enum.map(fn row ->
        %{
          name: text(row, "./P_7"),
          unit: text(row, "./P_8A"),
          quantity: text(row, "./P_8B"),
          unit_price: text(row, "./P_9A"),
          net_value: text(row, "./P_11"),
          vat_rate: text(row, "./P_12"),
          before?: text(row, "./StanPrzed") == "1"
        }
      end)

    if kind == :kor and not Enum.any?(rows, & &1.before?) and rows != [] do
      {:error, {:unsupported, "correction listing only differences"}}
    else
      rows
      |> Enum.reject(& &1.before?)
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {row, index}, {:ok, items} ->
        case item(row, index) do
          {:ok, item} -> {:cont, {:ok, [item | items]}}
          error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, items} -> {:ok, Enum.reverse(items), corrected_line_count(kind, rows)}
        error -> error
      end)
    end
  end

  defp corrected_line_count(:kor, rows), do: Enum.count(rows, & &1.before?)
  defp corrected_line_count(:vat, _rows), do: nil

  defp item(row, index) do
    quantity = if row.quantity, do: Decimal.new(row.quantity), else: Decimal.new(1)

    cond do
      not VatRate.valid?(row.vat_rate) ->
        {:error, {:unsupported, "VAT rate #{inspect(row.vat_rate)}"}}

      is_nil(row.unit_price) and is_nil(row.net_value) ->
        {:error, {:unsupported, "line without a net price"}}

      true ->
        {:ok,
         %{
           index: index,
           name: row.name,
           unit: row.unit || @default_unit,
           quantity: quantity,
           unit_price: unit_price(row, quantity),
           vat_rate: row.vat_rate
         }}
    end
  end

  # The line's net value (P_11) already accounts for a discount (P_10) the unit price leaves out.
  defp unit_price(%{net_value: nil, unit_price: unit_price}, _quantity), do: Decimal.new(unit_price)

  defp unit_price(%{net_value: net_value, unit_price: unit_price}, quantity) do
    net_value = Decimal.new(net_value)

    if unit_price && Decimal.equal?(Decimal.mult(Decimal.new(unit_price), quantity), net_value),
      do: Decimal.new(unit_price),
      else: Decimal.div(net_value, quantity)
  end

  defp payment_method(nil), do: {:ok, nil}

  defp payment_method(code) do
    case Map.fetch(@payment_methods, code) do
      {:ok, method} -> {:ok, method}
      :error -> {:error, {:unsupported, "payment method #{code}"}}
    end
  end

  defp address(doc, path) do
    case Enum.reject([text(doc, "#{path}/AdresL1"), text(doc, "#{path}/AdresL2")], &is_nil/1) do
      [] -> nil
      lines -> Enum.join(lines, ", ")
    end
  end

  defp date(nil), do: nil
  defp date(value), do: Date.from_iso8601!(value)

  defp text(node, path) do
    case node |> xpath(tns(sigil_x("#{path}/text()", ~c"os"))) |> to_string() |> String.trim() do
      "" -> nil
      value -> value
    end
  end

  defp tns(xpath), do: add_namespace(xpath, "", @fa3_namespace)
end
