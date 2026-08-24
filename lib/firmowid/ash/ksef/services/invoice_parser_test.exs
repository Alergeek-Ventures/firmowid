defmodule Firmowid.Ash.Ksef.Services.InvoiceParserTest do
  @moduledoc """
  Tests for FA(3) XML invoice parser.

  Validates parsing of namespaced XML, various payment methods, optional
  fields, sale_date fallback to issue_date, and correction invoice metadata.
  """

  use ExUnit.Case, async: true

  alias Firmowid.Ash.Ksef.Services.InvoiceParser

  describe "parse/1" do
    test "handles missing optional FormaPlatnosci" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>1234567890</NIP>
            <Nazwa>Test Seller</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres>
            <KodKraju>PL</KodKraju>
            <AdresL1>Test Address</AdresL1>
          </Adres>
        </Podmiot1>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-01-01</P_1>
          <P_2>TEST/001</P_2>
          <P_15>100.00</P_15>
          <RodzajFaktury>VAT</RodzajFaktury>
          <Platnosc>
            <TerminPlatnosci>
              <Termin>2025-01-15</Termin>
            </TerminPlatnosci>
          </Platnosc>
        </Fa>
      </Faktura>
      """

      assert {:ok, attrs} = InvoiceParser.parse(xml)

      # Payment method should be absent (not in map since not in XML)
      assert is_nil(attrs.payment_method)

      # But due_date should be present
      assert attrs.due_date == ~D[2025-01-15]

      # Core fields present
      assert attrs.seller_nip == "1234567890"
      assert attrs.seller == "Test Seller"
      assert attrs.invoice_identifier == "TEST/001"
      assert Decimal.equal?(Money.to_decimal(attrs.amount), Decimal.new("100.00"))
    end

    test "parses namespaced input with tns prefix" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <tns:Faktura xmlns:tns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <tns:Podmiot1>
          <tns:DaneIdentyfikacyjne>
            <tns:NIP>7191575524</tns:NIP>
            <tns:Nazwa>Namespaced Seller</tns:Nazwa>
          </tns:DaneIdentyfikacyjne>
          <tns:Adres>
            <tns:KodKraju>PL</tns:KodKraju>
            <tns:AdresL1>Namespaced Address</tns:AdresL1>
          </tns:Adres>
        </tns:Podmiot1>
        <tns:Fa>
          <tns:KodWaluty>PLN</tns:KodWaluty>
          <tns:P_1>2026-03-06</tns:P_1>
          <tns:P_2>NS/2026/001</tns:P_2>
          <tns:P_15>123.45</tns:P_15>
          <tns:RodzajFaktury>VAT</tns:RodzajFaktury>
          <tns:Platnosc>
            <tns:FormaPlatnosci>6</tns:FormaPlatnosci>
          </tns:Platnosc>
          <tns:FaWiersz>
            <tns:NrWierszaFa>1</tns:NrWierszaFa>
            <tns:P_7>Service A</tns:P_7>
            <tns:P_8B>2</tns:P_8B>
            <tns:P_9A>10.00</tns:P_9A>
          </tns:FaWiersz>
        </tns:Fa>
      </tns:Faktura>
      """

      assert {:ok, attrs} = InvoiceParser.parse(xml)

      assert attrs.seller_nip == "7191575524"
      assert attrs.seller == "Namespaced Seller"
      assert attrs.invoice_identifier == "NS/2026/001"
      assert attrs.issue_date == ~D[2026-03-06]
      assert Decimal.equal?(Money.to_decimal(attrs.amount), Decimal.new("123.45"))
      assert attrs.payment_method == :bank_transfer
      assert [%{name: "Service A", quantity: 2.0, price: 10.0}] = attrs.items_list
    end

    test "parses namespaced input with alternate prefix" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <foo:Faktura xmlns:foo="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <foo:Podmiot1>
          <foo:DaneIdentyfikacyjne>
            <foo:NIP>8000000000</foo:NIP>
            <foo:Nazwa>Other Prefix Seller</foo:Nazwa>
          </foo:DaneIdentyfikacyjne>
          <foo:Adres>
            <foo:KodKraju>PL</foo:KodKraju>
            <foo:AdresL1>Other Prefix Address</foo:AdresL1>
          </foo:Adres>
        </foo:Podmiot1>
        <foo:Fa>
          <foo:KodWaluty>EUR</foo:KodWaluty>
          <foo:P_1>2026-02-10</foo:P_1>
          <foo:P_2>RND/2026/002</foo:P_2>
          <foo:P_15>50.00</foo:P_15>
          <foo:RodzajFaktury>VAT</foo:RodzajFaktury>
          <foo:Platnosc>
            <foo:FormaPlatnosci>1</foo:FormaPlatnosci>
          </foo:Platnosc>
        </foo:Fa>
      </foo:Faktura>
      """

      assert {:ok, attrs} = InvoiceParser.parse(xml)

      assert attrs.seller_nip == "8000000000"
      assert attrs.seller == "Other Prefix Seller"
      assert attrs.invoice_identifier == "RND/2026/002"
      assert attrs.issue_date == ~D[2026-02-10]
      assert Decimal.equal?(Money.to_decimal(attrs.amount), Decimal.new("50.00"))
      assert attrs.payment_method == :cash
    end

    test "handles all FormaPlatnosci codes" do
      for {code, expected} <- [
            {"1", :cash},
            {"2", :card},
            {"3", :voucher},
            {"4", :check},
            {"5", :loan},
            {"6", :bank_transfer},
            {"7", :mobile}
          ] do
        xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
          <Podmiot1>
            <DaneIdentyfikacyjne>
              <NIP>1234567890</NIP>
              <Nazwa>Test</Nazwa>
            </DaneIdentyfikacyjne>
            <Adres>
              <KodKraju>PL</KodKraju>
              <AdresL1>Addr</AdresL1>
            </Adres>
          </Podmiot1>
          <Fa>
            <KodWaluty>PLN</KodWaluty>
            <P_1>2025-01-01</P_1>
            <P_2>INV/001</P_2>
            <P_15>100</P_15>
            <RodzajFaktury>VAT</RodzajFaktury>
            <Platnosc>
              <FormaPlatnosci>#{code}</FormaPlatnosci>
            </Platnosc>
          </Fa>
        </Faktura>
        """

        assert {:ok, attrs} = InvoiceParser.parse(xml)
        assert attrs.payment_method == expected, "Expected #{expected} for code #{code}"
      end
    end

    @tag capture_log: true
    test "returns error for invalid XML" do
      assert {:error, _} = InvoiceParser.parse("not xml at all")
    end

    test "handles XML with no Platnosc section" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>9999999999</NIP>
            <Nazwa>No Payment Seller</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres>
            <KodKraju>PL</KodKraju>
            <AdresL1>Some Address</AdresL1>
          </Adres>
        </Podmiot1>
        <Fa>
          <KodWaluty>EUR</KodWaluty>
          <P_1>2025-06-15</P_1>
          <P_2>EUR/2025/001</P_2>
          <P_15>250.50</P_15>
          <RodzajFaktury>VAT</RodzajFaktury>
          <FaWiersz>
            <NrWierszaFa>1</NrWierszaFa>
            <P_7>First item</P_7>
            <P_8B>3</P_8B>
            <P_9A>50.00</P_9A>
          </FaWiersz>
          <FaWiersz>
            <NrWierszaFa>2</NrWierszaFa>
            <P_7>Second item</P_7>
            <P_8B>2</P_8B>
            <P_9A>25.25</P_9A>
          </FaWiersz>
        </Fa>
      </Faktura>
      """

      assert {:ok, attrs} = InvoiceParser.parse(xml)

      # No payment fields
      assert is_nil(attrs.payment_method)
      assert is_nil(attrs.account_number)

      # Core fields work
      assert attrs.seller_nip == "9999999999"
      assert Money.to_currency_code(attrs.amount) == :EUR
      assert attrs.issue_date == ~D[2025-06-15]
      assert attrs.sale_date == ~D[2025-06-15]
      assert Decimal.equal?(Money.to_decimal(attrs.amount), Decimal.new("250.50"))
    end

    test "extracts explicit sale_date from P_6" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>1111111111</NIP>
            <Nazwa>Test</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres>
            <KodKraju>PL</KodKraju>
            <AdresL1>Addr</AdresL1>
          </Adres>
        </Podmiot1>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-03-15</P_1>
          <P_6>2025-03-10</P_6>
          <P_2>SALE/001</P_2>
          <P_15>1000</P_15>
          <RodzajFaktury>VAT</RodzajFaktury>
          <FaWiersz>
            <NrWierszaFa>1</NrWierszaFa>
            <P_7>Service provided</P_7>
            <P_8B>1</P_8B>
            <P_9A>1000</P_9A>
          </FaWiersz>
        </Fa>
      </Faktura>
      """

      assert {:ok, attrs} = InvoiceParser.parse(xml)

      # issue_date is P_1
      assert attrs.issue_date == ~D[2025-03-15]
      # sale_date is P_6 (different from issue_date)
      assert attrs.sale_date == ~D[2025-03-10]
    end

    test "extracts original invoice KSeF number for correction invoices" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>1234567890</NIP>
            <Nazwa>Test Seller</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres>
            <KodKraju>PL</KodKraju>
            <AdresL1>Test Address</AdresL1>
          </Adres>
        </Podmiot1>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-04-01</P_1>
          <P_2>KOR/001</P_2>
          <P_15>-10.00</P_15>
          <RodzajFaktury>KOR</RodzajFaktury>
          <DaneFaKorygowanej>
            <NrKSeFFaKorygowanej>KSEF-ORIGINAL-123</NrKSeFFaKorygowanej>
          </DaneFaKorygowanej>
        </Fa>
      </Faktura>
      """

      assert {:ok, attrs} = InvoiceParser.parse(xml)
      assert attrs.original_invoice_ksef_number == "KSEF-ORIGINAL-123"
    end

    test "returns error for unknown invoice type" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>1234567890</NIP>
            <Nazwa>Test</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres>
            <KodKraju>PL</KodKraju>
            <AdresL1>Addr</AdresL1>
          </Adres>
        </Podmiot1>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-01-01</P_1>
          <P_2>INV/001</P_2>
          <P_15>100</P_15>
          <RodzajFaktury>UNKNOWN</RodzajFaktury>
        </Fa>
      </Faktura>
      """

      assert {:error, error} = InvoiceParser.parse(xml)
      assert error =~ "Unknown FA(3) invoice type"
    end

    test "returns error for unknown payment method code" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Podmiot1>
          <DaneIdentyfikacyjne>
            <NIP>1234567890</NIP>
            <Nazwa>Test</Nazwa>
          </DaneIdentyfikacyjne>
          <Adres>
            <KodKraju>PL</KodKraju>
            <AdresL1>Addr</AdresL1>
          </Adres>
        </Podmiot1>
        <Fa>
          <KodWaluty>PLN</KodWaluty>
          <P_1>2025-01-01</P_1>
          <P_2>INV/001</P_2>
          <P_15>100</P_15>
          <RodzajFaktury>VAT</RodzajFaktury>
          <Platnosc>
            <FormaPlatnosci>99</FormaPlatnosci>
          </Platnosc>
        </Fa>
      </Faktura>
      """

      assert {:error, error} = InvoiceParser.parse(xml)
      assert error =~ "Unknown FA(3) payment method code"
    end
  end
end
