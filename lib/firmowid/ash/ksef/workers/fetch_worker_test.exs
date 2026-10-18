defmodule Firmowid.Ash.Ksef.Workers.FetchWorkerTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.OpenAIEnrichmentTestHelpers

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef.Services.Encryption
  alias Firmowid.Ash.Ksef.Services.SalesInvoiceImport.SkippedInvoicesError
  alias Firmowid.Ash.Ksef.Workers.FetchWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query

  setup do
    admin = admin_fixture()
    organization_id = admin.organization_id

    Cachex.put(:ksef, {:access_token, organization_id}, "test-access-token", expire: to_timeout(minute: 5))

    original_ksef_config = Application.fetch_env!(:firmowid, :ksef)
    original_openai_enrichment = Application.get_env(:firmowid, :openai_enrichment)

    Application.put_env(
      :firmowid,
      :ksef,
      Keyword.merge(original_ksef_config,
        base_url: "https://ksef.example",
        request_options: [plug: {Req.Test, :ksef_api}]
      )
    )

    Application.put_env(
      :firmowid,
      :openai_enrichment,
      request_options: [plug: {Req.Test, :openai_enrichment}]
    )

    stub_openai_enrichment_request()

    on_exit(fn ->
      Application.put_env(:firmowid, :ksef, original_ksef_config)
      restore_env(:openai_enrichment, original_openai_enrichment)
      Cachex.del(:ksef, {:access_token, organization_id})
    end)

    %{organization_id: organization_id, scope: ksef_scope(organization_id)}
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)

  test "imports invoices from a mocked completed export package", %{
    organization_id: organization_id,
    scope: scope
  } do
    ksef_number = "KSEF-IMPORT-#{System.unique_integer([:positive])}"
    storage_date = "2026-03-06T12:34:56Z"
    encryption_data = Encryption.generate_encryption_data()

    xml = invoice_xml(invoice_identifier: "FETCH/2026/001", total_amount: "123.45")

    {zip_binary, encrypted_package} =
      build_encrypted_package(
        [%{ksef_number: ksef_number, xml: xml, permanent_storage_date: storage_date}],
        encryption_data
      )

    part = package_part(zip_binary, encrypted_package, "https://ksef.example/downloads/package-1")

    Req.Test.stub(:ksef_api, fn conn ->
      case conn.request_path do
        "/invoices/exports/export-ref-1" ->
          Req.Test.json(conn, %{
            "status" => %{"code" => 200},
            "package" => %{"parts" => [part], "isTruncated" => false}
          })

        "/downloads/package-1" ->
          Plug.Conn.send_resp(conn, 200, encrypted_package)

        _ ->
          Plug.Conn.send_resp(conn, 404, "unexpected request: #{conn.request_path}")
      end
    end)

    assert :ok =
             perform_job(
               FetchWorker,
               poll_export_args(organization_id, encryption_data, "export-ref-1")
             )

    [invoice] = cost_invoices_by_ksef_number([ksef_number], scope)

    assert invoice.ksef_number == ksef_number
    assert invoice.invoice_identifier == "FETCH/2026/001"
    assert Decimal.equal?(Money.to_decimal(invoice.amount), Decimal.new("-123.45"))
    assert {:ok, permanent_storage_date, 0} = DateTime.from_iso8601(storage_date)
    assert invoice.ksef_permanent_storage_date == DateTime.to_naive(permanent_storage_date)
    assert %DateTime{} = invoice.ksef_downloaded_at
    assert invoice.blob_id
  end

  test "skips already imported KSeF invoices while importing new ones from a mocked export", %{
    organization_id: organization_id,
    scope: scope
  } do
    existing_ksef_number = "KSEF-DUP-#{System.unique_integer([:positive])}"
    new_ksef_number = "KSEF-NEW-#{System.unique_integer([:positive])}"
    storage_date = "2026-03-07T08:00:00Z"
    encryption_data = Encryption.generate_encryption_data()

    insert_existing_cost_invoice!(organization_id, existing_ksef_number)

    {zip_binary, encrypted_package} =
      build_encrypted_package(
        [
          %{
            ksef_number: existing_ksef_number,
            xml: invoice_xml(invoice_identifier: "FETCH/DUPLICATE/001", total_amount: "50.00"),
            permanent_storage_date: storage_date
          },
          %{
            ksef_number: new_ksef_number,
            xml: invoice_xml(invoice_identifier: "FETCH/NEW/002", total_amount: "75.50"),
            permanent_storage_date: storage_date
          }
        ],
        encryption_data
      )

    part = package_part(zip_binary, encrypted_package, "https://ksef.example/downloads/package-2")

    Req.Test.stub(:ksef_api, fn conn ->
      case conn.request_path do
        "/invoices/exports/export-ref-2" ->
          Req.Test.json(conn, %{
            "status" => %{"code" => 200},
            "package" => %{"parts" => [part], "isTruncated" => false}
          })

        "/downloads/package-2" ->
          Plug.Conn.send_resp(conn, 200, encrypted_package)

        _ ->
          Plug.Conn.send_resp(conn, 404, "unexpected request: #{conn.request_path}")
      end
    end)

    assert :ok =
             perform_job(
               FetchWorker,
               poll_export_args(organization_id, encryption_data, "export-ref-2")
             )

    invoices = cost_invoices_by_ksef_number([existing_ksef_number, new_ksef_number], scope)

    assert Enum.count(invoices, &(&1.ksef_number == existing_ksef_number)) == 1

    imported_invoice = Enum.find(invoices, &(&1.ksef_number == new_ksef_number))
    assert imported_invoice
    assert imported_invoice.invoice_identifier == "FETCH/NEW/002"
    assert Decimal.equal?(Money.to_decimal(imported_invoice.amount), Decimal.new("-75.50"))
  end

  test "imports sales invoices issued outside Firmowid and skips its own", %{
    organization_id: organization_id
  } do
    suffix = System.unique_integer([:positive])
    storage_date = "2026-03-08T09:00:00Z"

    confirmed =
      seed_sales_invoice!(organization_id, "FV/OWN/#{suffix}", ksef_number: "KSEF-OWN-#{suffix}")

    pending =
      seed_sales_invoice!(organization_id, "FV/PENDING/#{suffix}", locked_at: DateTime.utc_now())

    package = [
      %{ksef_number: confirmed.ksef_number, number: confirmed.invoice_number, kind: "VAT"},
      %{ksef_number: "KSEF-PENDING-#{suffix}", number: pending.invoice_number, kind: "VAT"},
      %{ksef_number: "KSEF-OTHER-#{suffix}", number: "OTHER/#{suffix}", kind: "VAT"},
      %{ksef_number: "KSEF-ADVANCE-#{suffix}", number: "ZAL/#{suffix}", kind: "ZAL"}
    ]

    package
    |> Enum.map(fn invoice ->
      %{
        ksef_number: invoice.ksef_number,
        xml: sales_invoice_xml(invoice.number, kind: invoice.kind),
        permanent_storage_date: storage_date
      }
    end)
    |> import_sales_package!(organization_id)
    |> skipped_ksef_numbers()
    |> then(&assert &1 == ["KSEF-ADVANCE-#{suffix}"])

    invoices =
      SalesInvoice
      |> Ash.Query.load(:sales_invoice_items)
      |> then(&SalesInvoice.list!(scope: sales_invoice_scope(organization_id), query: &1))
      |> Map.new(&{&1.invoice_number, &1})

    assert map_size(invoices) == 3

    assert invoices[confirmed.invoice_number].ksef_permanent_storage_date ==
             ~N[2026-03-08 09:00:00]

    assert is_nil(invoices[pending.invoice_number].ksef_number)

    imported = invoices["OTHER/#{suffix}"]
    assert imported.ksef_number == "KSEF-OTHER-#{suffix}"
    assert imported.issue_date == ~D[2026-03-06]
    assert imported.seller_display_name == "Other Software Seller"
    assert imported.buyer_full_name == "Kupiec Sp. z o.o."

    assert [%{name: "Usługa", unit_price: unit_price, vat_rate: "23"}] =
             imported.sales_invoice_items

    assert Decimal.equal?(unit_price, Decimal.new("100.00"))
  end

  test "imports corrections into the chain of the VAT invoice they correct", %{
    organization_id: organization_id
  } do
    suffix = System.unique_integer([:positive])
    original = "KSEF-VAT-#{suffix}"
    correction = "KSEF-KOR1-#{suffix}"
    both_lines = [{"A", "100.00", false}, {"B", "100.00", false}]

    [
      {original, sales_invoice_xml("FV/#{suffix}", lines: both_lines)},
      # A discount (P_10) leaves the unit price (P_9A) above the line's net value (P_11).
      {"KSEF-DISCOUNT-#{suffix}", sales_invoice_xml("RAB/#{suffix}", lines: [{"A", "100.00", "90.00", false}])},
      {correction,
       sales_invoice_xml("KOR1/#{suffix}",
         kind: "KOR",
         corrects: original,
         lines: [
           {"A", "100.00", true},
           {"B", "100.00", true},
           {"A", "50.00", false},
           {"B", "100.00", false}
         ]
       )},
      {"KSEF-KOR2-#{suffix}",
       sales_invoice_xml("KOR2/#{suffix}",
         kind: "KOR",
         corrects: correction,
         lines: [
           {"A", "50.00", true},
           {"B", "100.00", true},
           {"A", "40.00", false},
           {"B", "100.00", false}
         ]
       )},
      {"KSEF-PARTIAL-#{suffix}",
       sales_invoice_xml("PART/#{suffix}",
         kind: "KOR",
         corrects: original,
         lines: [{"A", "100.00", true}, {"A", "10.00", false}]
       )},
      # Rounding VAT per line (0.01 each) gives 0.08, while Firmowid's unrounded VAT gives 0.07.
      {"KSEF-ROUNDING-#{suffix}",
       sales_invoice_xml("ROUND/#{suffix}",
         lines: [{"A", "0.03", false}, {"B", "0.03", false}],
         gross_total: "0.08"
       )},
      {"KSEF-NOKSEF-#{suffix}",
       sales_invoice_xml("NOKSEF/#{suffix}",
         kind: "KOR",
         lines: [{"A", "100.00", true}, {"A", "10.00", false}]
       )},
      # A charge (Rozliczenie) makes the amount due differ from P_15.
      {"KSEF-SETTLEMENT-#{suffix}", sales_invoice_xml("ROZL/#{suffix}", settlement: true)},
      {"KSEF-PARTPAID-#{suffix}", sales_invoice_xml("PAID/#{suffix}", partially_paid: true)},
      # At the NBP test rate of 4.00, 23.00 EUR of VAT is 92.00 PLN, not 99.00.
      {"KSEF-EURVAT-#{suffix}", sales_invoice_xml("EUR/#{suffix}", currency: "EUR", vat_pln: "99.00")},
      {"KSEF-EUR-#{suffix}", sales_invoice_xml("EUROK/#{suffix}", currency: "EUR", vat_pln: "92.00")},
      {"KSEF-TIE-#{suffix}",
       sales_invoice_xml("TIE/#{suffix}",
         kind: "KOR",
         corrects: original,
         lines: [
           {"A", "40.00", true},
           {"B", "100.00", true},
           {"A", "30.00", false},
           {"B", "100.00", false}
         ]
       )}
    ]
    |> Enum.with_index()
    |> Enum.map(fn {{ksef_number, xml}, index} ->
      # KSEF-TIE is stored in the same second as KOR2, so their order is undetermined.
      second = if ksef_number == "KSEF-TIE-#{suffix}", do: 3, else: index

      %{
        ksef_number: ksef_number,
        xml: xml,
        permanent_storage_date: "2026-03-08T09:00:#{String.pad_leading("#{second}", 2, "0")}Z"
      }
    end)
    |> import_sales_package!(organization_id)
    |> skipped_ksef_numbers()
    |> then(
      &assert &1 ==
                Enum.sort([
                  "KSEF-PARTPAID-#{suffix}",
                  "KSEF-EURVAT-#{suffix}",
                  "KSEF-SETTLEMENT-#{suffix}",
                  "KSEF-TIE-#{suffix}",
                  "KSEF-PARTIAL-#{suffix}",
                  "KSEF-ROUNDING-#{suffix}",
                  "KSEF-NOKSEF-#{suffix}"
                ])
    )

    scope = sales_invoice_scope(organization_id)

    invoices =
      SalesInvoice
      |> Ash.Query.load([:gross_value, :corrected_invoice_id, latest_correction: :invoice_number])
      |> then(&SalesInvoice.list!(scope: scope, query: &1))
      |> Map.new(&{&1.invoice_number, &1})

    assert invoices |> Map.keys() |> Enum.sort() ==
             Enum.sort([
               "FV/#{suffix}",
               "RAB/#{suffix}",
               "KOR1/#{suffix}",
               "KOR2/#{suffix}",
               "EUROK/#{suffix}"
             ])

    assert Decimal.equal?(invoices["RAB/#{suffix}"].gross_value, Decimal.new("110.70"))

    vat = invoices["FV/#{suffix}"]
    assert invoices["KOR1/#{suffix}"].corrected_invoice_id == vat.id
    assert invoices["KOR2/#{suffix}"].corrected_invoice_id == vat.id
    assert vat.latest_correction.invoice_number == "KOR2/#{suffix}"
  end

  defp ksef_scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :ksef_session},
      tenant: organization_id
    }
  end

  defp sales_invoice_scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :sales_invoice_processor},
      tenant: organization_id
    }
  end

  defp poll_export_args(organization_id, encryption_data, reference_number) do
    %{
      "action" => "poll_export",
      "organization_id" => organization_id,
      "reference_number" => reference_number,
      "encryption_key" => Base.encode64(encryption_data.key),
      "encryption_iv" => Base.encode64(encryption_data.iv),
      "date_from" => "2026-03-01T00:00:00Z"
    }
  end

  defp build_encrypted_package(invoices, encryption_data) do
    metadata_json = metadata_json(invoices)

    zip_entries = [
      {~c"_metadata.json", metadata_json}
      | Enum.map(invoices, fn %{ksef_number: ksef_number, xml: xml} ->
          {String.to_charlist("#{ksef_number}.xml"), xml}
        end)
    ]

    {:ok, {_name, zip_binary}} = :zip.create(~c"ksef-export.zip", zip_entries, [:memory])

    encrypted_package =
      Encryption.encrypt_aes256_cbc(zip_binary, encryption_data.key, encryption_data.iv)

    {zip_binary, encrypted_package}
  end

  defp metadata_json(invoices) do
    invoices
    |> Enum.map(fn %{ksef_number: ksef_number, permanent_storage_date: permanent_storage_date} ->
      %{
        "ksefNumber" => ksef_number,
        "permanentStorageDate" => permanent_storage_date
      }
    end)
    |> then(&%{"invoices" => &1})
    |> Jason.encode!()
  end

  defp package_part(zip_binary, encrypted_package, url) do
    encrypted_hash = :crypto.hash(:sha256, encrypted_package)
    part_hash = :crypto.hash(:sha256, zip_binary)

    %{
      "ordinalNumber" => 1,
      "url" => url,
      "method" => "GET",
      "expirationDate" => DateTime.utc_now() |> DateTime.shift(hour: 1) |> DateTime.to_iso8601(),
      "partHash" => Base.encode64(part_hash),
      "encryptedPartHash" => Base.encode64(encrypted_hash)
    }
  end

  defp cost_invoices_by_ksef_number(ksef_numbers, scope) do
    CostInvoice
    |> Ash.Query.filter(ksef_number in ^ksef_numbers)
    |> Ash.Query.sort(ksef_number: :asc)
    |> Ash.Query.load([:blob])
    |> then(&CostInvoice.list!(scope: scope, query: &1))
  end

  defp insert_existing_cost_invoice!(organization_id, ksef_number) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: "Existing Supplier Sp. z o.o.",
      seller_display_name: "Existing Supplier",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      sale_date: ~D[2026-03-01],
      issue_date: ~D[2026-03-01],
      due_date: ~D[2026-03-15],
      amount: Money.new!("PLN", Decimal.new("-50.00")),
      description: "Existing imported invoice",
      invoice_identifier: "EXISTING/#{System.unique_integer([:positive])}",
      skip_invoicing: false,
      organization_id: organization_id,
      ksef_number: ksef_number,
      ksef_permanent_storage_date: ~N[2026-03-01 08:00:00],
      ksef_downloaded_at: DateTime.utc_now()
    })
  end

  defp invoice_xml(opts) do
    invoice_identifier = Keyword.fetch!(opts, :invoice_identifier)
    total_amount = Keyword.fetch!(opts, :total_amount)

    """
    <?xml version="1.0" encoding="utf-8"?>
    <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
      <Podmiot1>
        <DaneIdentyfikacyjne>
          <NIP>7191575524</NIP>
          <Nazwa>Mocked Supplier</Nazwa>
        </DaneIdentyfikacyjne>
        <Adres>
          <KodKraju>PL</KodKraju>
          <AdresL1>ul. Mockowana 10, 00-100 Warszawa</AdresL1>
        </Adres>
      </Podmiot1>
      <Fa>
        <KodWaluty>#{Keyword.get(opts, :currency, "PLN")}</KodWaluty>
        <P_1>2026-03-06</P_1>
        <P_2>#{invoice_identifier}</P_2>
        <P_15>#{total_amount}</P_15>
        <RodzajFaktury>VAT</RodzajFaktury>
        <Platnosc>
          #{if opts[:partially_paid], do: "<ZnacznikZaplatyCzesciowej>1</ZnacznikZaplatyCzesciowej><ZaplataCzesciowa><KwotaZaplatyCzesciowej>50.00</KwotaZaplatyCzesciowej><DataZaplatyCzesciowej>2026-03-06</DataZaplatyCzesciowej></ZaplataCzesciowa>"}
          <FormaPlatnosci>6</FormaPlatnosci>
          <TerminPlatnosci>
            <Termin>2026-03-20</Termin>
          </TerminPlatnosci>
        </Platnosc>
        <FaWiersz>
          <NrWierszaFa>1</NrWierszaFa>
          <P_7>Imported line</P_7>
          <P_8B>1</P_8B>
          <P_9A>#{total_amount}</P_9A>
        </FaWiersz>
      </Fa>
    </Faktura>
    """
  end

  defp seed_sales_invoice!(organization_id, invoice_number, attrs) do
    Ash.Seed.seed!(
      SalesInvoice,
      Map.merge(
        %{
          invoice_number: invoice_number,
          issue_date: ~D[2026-03-06],
          currency: "PLN",
          buyer_full_name: "Kupiec Sp. z o.o.",
          organization_id: organization_id
        },
        Map.new(attrs)
      )
    )
  end

  defp import_sales_package!(invoices, organization_id) do
    reference = "export-ref-#{System.unique_integer([:positive])}"
    encryption_data = Encryption.generate_encryption_data()
    {zip_binary, encrypted_package} = build_encrypted_package(invoices, encryption_data)

    part =
      package_part(zip_binary, encrypted_package, "https://ksef.example/downloads/#{reference}")

    Req.Test.stub(:ksef_api, fn conn ->
      case conn.request_path do
        "/invoices/exports/" <> ^reference ->
          Req.Test.json(conn, %{
            "status" => %{"code" => 200},
            "package" => %{"parts" => [part], "isTruncated" => false}
          })

        "/downloads/" <> ^reference ->
          Plug.Conn.send_resp(conn, 200, encrypted_package)

        _ ->
          Plug.Conn.send_resp(conn, 404, "unexpected request: #{conn.request_path}")
      end
    end)

    args =
      organization_id
      |> poll_export_args(encryption_data, reference)
      |> Map.put("subject_type", "Subject1")

    perform_job(FetchWorker, args)
  end

  defp skipped_ksef_numbers({:error, %SkippedInvoicesError{skipped: skipped}}),
    do: skipped |> Enum.map(& &1.ksef_number) |> Enum.sort()

  # Lines are {name, unit price, before?} or {name, unit price, net value, before?}, one unit each at 23% VAT.
  defp sales_invoice_xml(invoice_number, opts) do
    kind = Keyword.get(opts, :kind, "VAT")
    lines = Keyword.get(opts, :lines, [{"Usługa", "100.00", false}])

    lines =
      Enum.map(lines, fn
        {name, price, before?} -> {name, price, price, before?}
        line -> line
      end)

    # P_15 of a correction is the change it makes.
    gross_total =
      Keyword.get_lazy(opts, :gross_total, fn ->
        lines
        |> Enum.map(fn {_name, _price, net, before?} ->
          gross = Decimal.mult(Decimal.new(net), Decimal.new("1.23"))
          if before?, do: Decimal.negate(gross), else: gross
        end)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        |> Decimal.round(2)
      end)

    rows =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join(fn {{name, price, net, before?}, index} ->
        """
        <FaWiersz>
          <NrWierszaFa>#{index}</NrWierszaFa>
          <P_7>#{name}</P_7>
          <P_8A>szt.</P_8A>
          <P_8B>1</P_8B>
          <P_9A>#{price}</P_9A>
          <P_11>#{net}</P_11>
          <P_12>23</P_12>
          #{if before?, do: "<StanPrzed>1</StanPrzed>"}
        </FaWiersz>
        """
      end)

    corrected =
      case Keyword.fetch(opts, :corrects) do
        {:ok, ksef_number} ->
          "<NrKSeF>1</NrKSeF><NrKSeFFaKorygowanej>#{ksef_number}</NrKSeFFaKorygowanej>"

        :error ->
          "<NrKSeFN>1</NrKSeFN>"
      end

    """
    <?xml version="1.0" encoding="utf-8"?>
    <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
      <Podmiot1>
        <DaneIdentyfikacyjne>
          <NIP>7191575524</NIP>
          <Nazwa>Other Software Seller</Nazwa>
        </DaneIdentyfikacyjne>
        <Adres>
          <KodKraju>PL</KodKraju>
          <AdresL1>ul. Mockowana 10, 00-100 Warszawa</AdresL1>
        </Adres>
      </Podmiot1>
      <Podmiot2>
        <DaneIdentyfikacyjne>
          <NIP>5260250274</NIP>
          <Nazwa>Kupiec Sp. z o.o.</Nazwa>
        </DaneIdentyfikacyjne>
        <Adres>
          <KodKraju>PL</KodKraju>
          <AdresL1>ul. Kupiecka 2, 00-002 Kraków</AdresL1>
        </Adres>
      </Podmiot2>
      <Fa>
        <KodWaluty>#{Keyword.get(opts, :currency, "PLN")}</KodWaluty>
        <P_1>2026-03-06</P_1>
        <P_2>#{invoice_number}</P_2>
        #{if vat_pln = opts[:vat_pln], do: "<P_13_1>100.00</P_13_1><P_14_1>23.00</P_14_1><P_14_1W>#{vat_pln}</P_14_1W>"}
        <P_15>#{gross_total}</P_15>
        <RodzajFaktury>#{kind}</RodzajFaktury>
        #{if kind == "KOR", do: "<DaneFaKorygowanej><DataWystFaKorygowanej>2026-03-06</DataWystFaKorygowanej><NrFaKorygowanej>X</NrFaKorygowanej>#{corrected}</DaneFaKorygowanej>"}
        #{rows}
        #{if opts[:settlement], do: "<Rozliczenie><Obciazenia><Kwota>20.00</Kwota><Powod>Opłata</Powod></Obciazenia><SumaObciazen>20.00</SumaObciazen><DoZaplaty>143.00</DoZaplaty></Rozliczenie>"}
        <Platnosc>
          <TerminPlatnosci>
            <Termin>2026-03-20</Termin>
          </TerminPlatnosci>
          #{if opts[:partially_paid], do: "<ZnacznikZaplatyCzesciowej>1</ZnacznikZaplatyCzesciowej><ZaplataCzesciowa><KwotaZaplatyCzesciowej>50.00</KwotaZaplatyCzesciowej><DataZaplatyCzesciowej>2026-03-06</DataZaplatyCzesciowej></ZaplataCzesciowa>"}
          <FormaPlatnosci>6</FormaPlatnosci>
          <RachunekBankowy>
            <NrRB>12345678901234567890123456</NrRB>
          </RachunekBankowy>
        </Platnosc>
      </Fa>
    </Faktura>
    """
  end
end
