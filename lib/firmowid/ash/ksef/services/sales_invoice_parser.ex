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
  makes), its VAT per rate group with any PLN conversion and, for a correction, the
  lines it lists before the correction, so the import can reject a document whose
  recalculated amounts or lines do not match it.
  """

  import SweetXml

  alias Firmowid.Ash.Invoicing.CountryCodes
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
  # The VAT rates each P_13_x net total sums.
  @net_groups %{
    "1" => ["23", "22"],
    "2" => ["8", "7"],
    "3" => ["5"],
    "4" => ["4"],
    "5" => ["3"],
    "6_1" => ["0 KR"],
    "6_2" => ["0 WDT"],
    "6_3" => ["0 EX"],
    "7" => ["zw"],
    "8" => ["np I"],
    "9" => ["np II"],
    "10" => ["oo"]
  }
  # Annotations whose procedures the sales invoice does not represent, set when "1".
  @unsupported_annotations %{
    "P_17" => "self-billing (P_17)",
    "P_18A" => "split payment (P_18A)",
    "NoweSrodkiTransportu/P_22" => "new means of transport (P_22)",
    "P_23" => "triangular procedure (P_23)",
    "PMarzy/P_PMarzy" => "margin scheme (P_PMarzy)"
  }
  # Elements the sales invoice cannot keep: other parties, a correction of the seller's data or
  # of the invoice number, the OSS procedure's rates and rarer tax markers.
  @unsupported_elements [
    {"Podmiot3", "third party (Podmiot3)"},
    {"PodmiotUpowazniony", "authorized party (PodmiotUpowazniony)"},
    {"Fa/Podmiot1K", "correction of seller data (Podmiot1K)"},
    {"Fa/NrFaKorygowany", "corrected invoice number (NrFaKorygowany)"},
    {"Fa/FaWiersz/P_12_XII", "OSS rate (P_12_XII)"},
    {"Fa/TypKorekty", "correction tax period (TypKorekty)"},
    {"Fa/FaWiersz/Procedura", "line procedure (Procedura)"},
    {"Fa/FaWiersz/P_12_Zal_15", "annex 15 goods (P_12_Zal_15)"},
    {"Fa/FaWiersz/KwotaAkcyzy", "excise duty (KwotaAkcyzy)"},
    {"Fa/ZwrotAkcyzy", "excise refund (ZwrotAkcyzy)"},
    {"Fa/WarunkiTransakcji/PodmiotPosredniczacy", "intermediary in a chain transaction (PodmiotPosredniczacy)"},
    {"Podmiot1/PrefiksPodatnika", "seller VAT prefix (PrefiksPodatnika)"}
  ]
  @unsupported_payment [
    {"RachunekBankowyFaktora", "factoring account (RachunekBankowyFaktora)"},
    {"Skonto", "cash discount (Skonto)"},
    {"PlatnoscInna", "other payment method (PlatnoscInna)"},
    {"RachunekBankowy/SWIFT", "bank account SWIFT"},
    {"RachunekBankowy/OpisRachunku", "bank account description (OpisRachunku)"},
    {"RachunekBankowy/RachunekWlasnyBanku", "bank's own account (RachunekWlasnyBanku)"},
    {"LinkDoPlatnosci", "payment link (LinkDoPlatnosci)"},
    {"IPKSeF", "payment identifier (IPKSeF)"}
  ]
  # FA(3) makes the unit optional, while every Firmowid line has one.
  @default_unit "szt."

  @doc """
  Parses FA(3) XML into attributes for `SalesInvoice.import_from_ksef`, including
  `:sales_invoice_items`, `:ksef_gross_total` and, for a correction,
  `:corrected_invoice_ksef_number` and `:corrected_lines` (the net value and VAT rate of
  each line it lists before the correction).
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, {:unsupported, String.t()} | term()}
  def parse(xml) when is_binary(xml) do
    doc = SweetXml.parse(xml, namespace_conformant: true)

    with {:ok, kind} <- invoice_kind(text(doc, "/Faktura/Fa/RodzajFaktury")),
         :ok <- no_settlement(doc),
         :ok <- single_sale_date(doc),
         :ok <- no_partial_payment(doc),
         :ok <- supported_annotations(doc),
         :ok <- buyer_country_consistent(doc),
         :ok <- addresses_fit(doc),
         :ok <- single_footer(doc),
         {:ok, items, corrected_lines} <- items(doc, kind),
         :ok <- one_rate_per_group(items),
         :ok <- single_due_date(doc),
         :ok <- supported_payment(doc),
         :ok <- no_unsupported_elements(doc),
         :ok <- single_seller_account(doc),
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
         related_parties: text(doc, "/Faktura/Fa/TP") == "1",
         receipt_invoice: text(doc, "/Faktura/Fa/FP") == "1",
         invoice_note: text(doc, "/Faktura/Stopka/Informacje/StopkaFaktury"),
         correction_reason: text(doc, "/Faktura/Fa/PrzyczynaKorekty"),
         corrected_invoice_ksef_number: text(doc, "/Faktura/Fa/DaneFaKorygowanej/NrKSeFFaKorygowanej"),
         corrected_lines: corrected_lines,
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

  # Firmowid keeps one buyer country for both the tax ID and the address, and derives the tax ID
  # kind from it, so a Polish NIP, an EU VAT number or another country's ID with an address in
  # another country would change the buyer's identity on a correction.
  defp buyer_country_consistent(doc) do
    {id_kind, id_country} = buyer_id_country(doc)
    address_country = text(doc, "/Faktura/Podmiot2/Adres/KodKraju")

    cond do
      # Firmowid would treat an EU buyer's ID as an EU VAT number.
      id_kind == :nr_id and CountryCodes.eu_country?(id_country) ->
        {:error, {:unsupported, "EU buyer identified by NrID"}}

      is_nil(id_country) or is_nil(address_country) or id_country == address_country ->
        :ok

      true ->
        {:error, {:unsupported, "buyer tax ID country differs from address country"}}
    end
  end

  # Firmowid keeps an address as one line, which FA(3) limits to 512 characters.
  defp addresses_fit(doc) do
    paths = [
      "/Faktura/Podmiot1/Adres",
      "/Faktura/Podmiot2/Adres",
      "/Faktura/Podmiot2/AdresKoresp"
    ]

    # XSD lengths count code points, not graphemes.
    if Enum.all?(paths, &(length(String.to_charlist(address(doc, &1) || "")) <= 512)),
      do: :ok,
      else: {:error, {:unsupported, "address longer than one FA(3) address line"}}
  end

  # Firmowid keeps one invoice note; several footers would be run together.
  defp single_footer(doc) do
    if length(xpath(doc, tns(~x"/Faktura/Stopka/Informacje/StopkaFaktury"l))) > 1,
      do: {:error, {:unsupported, "several invoice footers (StopkaFaktury)"}},
      else: :ok
  end

  defp buyer_id_country(doc) do
    id = "/Faktura/Podmiot2/DaneIdentyfikacyjne"

    cond do
      text(doc, "#{id}/NIP") -> {:nip, "PL"}
      text(doc, "#{id}/NrVatUE") -> {:vat_ue, text(doc, "#{id}/KodUE")}
      text(doc, "#{id}/NrID") -> {:nr_id, text(doc, "#{id}/KodKraju")}
      true -> {:none, nil}
    end
  end

  defp no_unsupported_elements(doc) do
    case Enum.find(@unsupported_elements, fn {path, _reason} ->
           xpath(doc, tns(sigil_x("/Faktura/#{path}", ~c"o")))
         end) do
      nil -> :ok
      {_path, reason} -> {:error, {:unsupported, reason}}
    end
  end

  # Firmowid renders the seller's address in Poland and pays to one account.
  defp single_seller_account(doc) do
    cond do
      text(doc, "/Faktura/Podmiot1/Adres/KodKraju") not in [nil, "PL"] ->
        {:error, {:unsupported, "seller address outside Poland"}}

      length(xpath(doc, tns(~x"/Faktura/Fa/Platnosc/RachunekBankowy"l))) > 1 ->
        {:error, {:unsupported, "several bank accounts"}}

      true ->
        :ok
    end
  end

  # Payment instructions the sales invoice does not show: a factor's account, a cash discount
  # for early payment, a payment method described in text instead of a code, bank account
  # details beyond its number, or a payment link.
  defp supported_payment(doc) do
    case Enum.find(@unsupported_payment, fn {element, _reason} ->
           xpath(doc, tns(sigil_x("/Faktura/Fa/Platnosc/#{element}", ~c"o")))
         end) do
      nil -> :ok
      {_element, reason} -> {:error, {:unsupported, reason}}
    end
  end

  # A sales invoice has one due date; instalments or a descriptive term would be lost.
  defp single_due_date(doc) do
    terms = "/Faktura/Fa/Platnosc/TerminPlatnosci"

    cond do
      length(xpath(doc, tns(~x"#{terms}"l))) > 1 ->
        {:error, {:unsupported, "several payment terms"}}

      xpath(doc, tns(~x"#{terms}/TerminOpis"o)) && is_nil(text(doc, "#{terms}/Termin")) ->
        {:error, {:unsupported, "descriptive payment term (TerminOpis)"}}

      true ->
        :ok
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

    mail_address = address(doc, "/Faktura/Podmiot2/AdresKoresp")

    Map.merge(names, %{
      buyer_id: buyer_id,
      buyer_country: country,
      buyer_address: address(doc, "/Faktura/Podmiot2/Adres"),
      buyer_is_different_mail_address: not is_nil(mail_address),
      buyer_mail_address: mail_address,
      buyer_mail_country: text(doc, "/Faktura/Podmiot2/AdresKoresp/KodKraju"),
      # Up to three contacts may be listed; the invoice keeps the first.
      buyer_email: first_text(doc, "/Faktura/Podmiot2/DaneKontaktowe/Email"),
      buyer_phone: first_text(doc, "/Faktura/Podmiot2/DaneKontaktowe/Telefon")
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

    net_groups =
      for {group, rates} <- @net_groups do
        # An omitted group carries no net value.
        %{rates: rates, net: Decimal.new(text(doc, "/Faktura/Fa/P_13_#{group}") || "0")}
      end

    %{groups: groups, net_groups: net_groups, line_rates: line_rates}
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
          gross_value: text(row, "./P_11A"),
          vat_value: text(row, "./P_11Vat"),
          vat_rate: text(row, "./P_12"),
          gtu: text(row, "./GTU"),
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
        {:ok, items} -> {:ok, Enum.reverse(items), corrected_lines(kind, rows)}
        error -> error
      end)
    end
  end

  # FA(3) sums 22% with 23% and 7% with 8% in one total, which Firmowid's correction
  # summary would write twice.
  defp one_rate_per_group(items) do
    rates = MapSet.new(items, & &1.vat_rate)

    if Enum.any?([["22", "23"], ["7", "8"]], &Enum.all?(&1, fn rate -> rate in rates end)),
      do: {:error, {:unsupported, "two VAT rates of one FA(3) group"}},
      else: :ok
  end

  defp corrected_lines(:vat, _rows), do: nil

  defp corrected_lines(:kor, rows) do
    for %{before?: true} = row <- rows do
      quantity = if row.quantity, do: Decimal.new(row.quantity), else: Decimal.new(1)

      net =
        if row.net_value,
          do: Decimal.new(row.net_value),
          else: Decimal.mult(Decimal.new(row.unit_price), quantity)

      %{net: net, vat_rate: row.vat_rate}
    end
  end

  defp item(row, index) do
    quantity = if row.quantity, do: Decimal.new(row.quantity), else: Decimal.new(1)

    with :ok <- check_line(row, quantity) do
      {:ok,
       %{
         index: index,
         name: row.name,
         unit: row.unit || @default_unit,
         quantity: quantity,
         unit_price: unit_price(row, quantity),
         vat_rate: row.vat_rate,
         gtu: row.gtu
       }}
    end
  end

  defp check_line(row, quantity) do
    cond do
      not VatRate.valid?(row.vat_rate) ->
        {:error, {:unsupported, "VAT rate #{inspect(row.vat_rate)}"}}

      is_nil(row.unit_price) and is_nil(row.net_value) ->
        {:error, {:unsupported, "line without a net price"}}

      is_nil(unit_price(row, quantity)) ->
        {:error, {:unsupported, "line net value not divisible by its quantity"}}

      not line_amounts_match?(row, quantity) ->
        {:error, {:unsupported, "line gross or VAT differs from Firmowid's calculation"}}

      # Firmowid writes unit prices to the grosz on the documents it renders, e.g. corrections.
      Decimal.scale(Decimal.normalize(unit_price(row, quantity))) > 2 ->
        {:error, {:unsupported, "unit price below the grosz"}}

      true ->
        :ok
    end
  end

  # A line's stated gross (P_11A) and VAT (P_11Vat) must be what Firmowid shows for it.
  defp line_amounts_match?(row, quantity) do
    net = Decimal.mult(unit_price(row, quantity), quantity)
    vat = Decimal.mult(net, Decimal.div(VatRate.to_numeric(row.vat_rate), 100))

    Enum.all?([{row.vat_value, vat}, {row.gross_value, Decimal.add(net, vat)}], fn
      {nil, _amount} -> true
      {stated, amount} -> Decimal.equal?(Decimal.new(stated), Decimal.round(amount, 2))
    end)
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

  defp first_text(node, path) do
    case xpath(node, tns(sigil_x("#{path}/text()", ~c"ls"))) do
      [value | _] -> String.trim(value)
      [] -> nil
    end
  end

  defp tns(xpath), do: add_namespace(xpath, "", @fa3_namespace)
end
