defmodule Firmowid.Ash.Ksef.Services.SalesInvoiceParser do
  @moduledoc """
  Parses an FA(3) sales invoice issued outside Firmowid into `SalesInvoice` attributes.

  It reads the elements `InvoiceRenderer` writes. A document the sales invoice cannot
  represent is rejected with `{:error, {:unsupported, reason}}`: invoice kinds other than
  VAT and KOR, charges or deductions or a partial payment changing the amount due, a sale period or per-line
  sale dates instead of one sale date, gross-only lines, VAT rates
  outside `VatRate`, and corrections listing only differences instead of the state
  before and after.

  It also reports the document's gross total (`P_15`, for a correction the change it
  makes) and, for a correction, how many lines it lists before the correction, so the
  import can reject a document whose recalculated amounts or lines do not match it.
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
  # The VAT rates each P_14_x (and its P_14_xW) sums; the 3% rate has no PLN amount.
  @vat_groups %{1 => ["23", "22"], 2 => ["8", "7"], 3 => ["5"], 4 => ["4"], 5 => ["3"]}
  # Annotations whose procedures the sales invoice does not represent, set when "1".
  @unsupported_annotations %{
    "P_17" => "self-billing (P_17)",
    "P_18A" => "split payment (P_18A)",
    "NoweSrodkiTransportu/P_22" => "new means of transport (P_22)",
    "P_23" => "triangular procedure (P_23)",
    "PMarzy/P_PMarzy" => "margin scheme (P_PMarzy)"
  }
  # FA(3) makes the unit optional, while every Firmowid line has one.
  @default_unit "szt."

  @doc """
  Parses FA(3) XML into attributes for `SalesInvoice.import_from_ksef`, including
  `:sales_invoice_items`, `:ksef_gross_total` and, for a correction,
  `:corrected_invoice_ksef_number` and `:corrected_line_count`.
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, {:unsupported, String.t()} | term()}
  def parse(xml) when is_binary(xml) do
    doc = SweetXml.parse(xml, namespace_conformant: true)

    with {:ok, kind} <- invoice_kind(text(doc, "/Faktura/Fa/RodzajFaktury")),
         :ok <- no_settlement(doc),
         :ok <- single_sale_date(doc),
         :ok <- no_partial_payment(doc),
         :ok <- supported_annotations(doc),
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
         is_cash_account: text(doc, "/Faktura/Fa/Adnotacje/P_16") == "1",
         invoice_note: text(doc, "/Faktura/Stopka/Informacje/StopkaFaktury"),
         correction_reason: text(doc, "/Faktura/Fa/PrzyczynaKorekty"),
         corrected_invoice_ksef_number: text(doc, "/Faktura/Fa/DaneFaKorygowanej/NrKSeFFaKorygowanej"),
         corrected_line_count: corrected_line_count,
         ksef_gross_total: Decimal.new(text(doc, "/Faktura/Fa/P_15")),
         ksef_vat: vat_groups(doc),
         sales_invoice_items: items
       })}
    end
  rescue
    e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  # Charges and deductions (Rozliczenie) change the amount due, which Firmowid always takes from the lines.
  defp no_settlement(doc) do
    case xpath(doc, tns(~x"/Faktura/Fa/Rozliczenie"o)) do
      nil -> :ok
      _settlement -> {:error, {:unsupported, "charges or deductions (Rozliczenie)"}}
    end
  end

  # A sales invoice has one sale date; a period (OkresFa) or per-line dates (P_6A) would be lost.
  defp single_sale_date(doc) do
    cond do
      xpath(doc, tns(~x"/Faktura/Fa/OkresFa"o)) ->
        {:error, {:unsupported, "sale period (OkresFa)"}}

      xpath(doc, tns(~x"/Faktura/Fa/FaWiersz/P_6A"o)) ->
        {:error, {:unsupported, "per-line sale dates (P_6A)"}}

      true ->
        :ok
    end
  end

  defp supported_annotations(doc) do
    case Enum.find(@unsupported_annotations, fn {path, _reason} ->
           text(doc, "/Faktura/Fa/Adnotacje/#{path}") == "1"
         end) do
      nil -> :ok
      {_path, reason} -> {:error, {:unsupported, reason}}
    end
  end

  # Firmowid shows the whole amount as due, which a partially paid document does not owe.
  defp no_partial_payment(doc) do
    if text(doc, "/Faktura/Fa/Platnosc/ZnacznikZaplatyCzesciowej") == "1",
      do: {:error, {:unsupported, "partial payment (ZaplataCzesciowa)"}},
      else: :ok
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

  # The foreign template shows VAT as not applicable, so it only fits a document without any,
  # including a correction's lines before it.
  defp invoice_type(doc) do
    taxed? =
      doc
      |> xpath(tns(~x"/Faktura/Fa/FaWiersz/P_12/text()"ls))
      |> Enum.any?(&Decimal.gt?(VatRate.to_numeric(String.trim(&1)), 0))

    if taxed? or text(doc, "/Faktura/Podmiot2/Adres/KodKraju") in [nil, "PL"],
      do: :poland,
      else: :foreign
  end

  # The document's VAT per rate group (P_14_x), with its PLN amount (P_14_xW) for a foreign
  # currency, and the exchange rates stated on lines (KursWaluty).
  defp vat_groups(doc) do
    groups =
      for {group, rates} <- @vat_groups do
        vat_pln = text(doc, "/Faktura/Fa/P_14_#{group}W")
        # An omitted group carries no VAT.
        vat = text(doc, "/Faktura/Fa/P_14_#{group}") || "0"
        %{rates: rates, vat: Decimal.new(vat), vat_pln: vat_pln && Decimal.new(vat_pln)}
      end

    line_rates =
      doc
      |> xpath(tns(~x"/Faktura/Fa/FaWiersz/KursWaluty/text()"ls))
      |> Enum.map(&(&1 |> String.trim() |> Decimal.new()))

    %{groups: groups, line_rates: line_rates}
  end

  defp exemption(doc) do
    zwolnienie = "/Faktura/Fa/Adnotacje/Zwolnienie"

    cond do
      basis = text(doc, "#{zwolnienie}/P_19A") ->
        case Map.fetch(@exemption_types, basis) do
          {:ok, type} -> %{vat_exemption_type: type}
          :error -> %{vat_exemption_type: :other, vat_exemption_basis: basis}
        end

      basis = text(doc, "#{zwolnienie}/P_19B") ->
        if basis == VatExemption.label(:directive_2006_112),
          do: %{vat_exemption_type: :directive_2006_112},
          else: %{vat_exemption_type: :other, vat_exemption_basis: basis}

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

      is_nil(unit_price(row, quantity)) ->
        {:error, {:unsupported, "line net value not divisible by its quantity"}}

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
  # A unit price that does not multiply back to it exactly would shift the totals, so it is nil.
  defp unit_price(%{net_value: nil, unit_price: unit_price}, _quantity), do: Decimal.new(unit_price)

  defp unit_price(%{net_value: net_value, unit_price: unit_price}, quantity) do
    net_value = Decimal.new(net_value)
    multiplies_back? = &Decimal.equal?(Decimal.mult(&1, quantity), net_value)

    cond do
      unit_price && multiplies_back?.(Decimal.new(unit_price)) -> Decimal.new(unit_price)
      Decimal.eq?(quantity, 0) -> nil
      multiplies_back?.(Decimal.div(net_value, quantity)) -> Decimal.div(net_value, quantity)
      true -> nil
    end
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
