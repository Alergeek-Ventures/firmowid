defmodule Firmowid.Ksef.InvoiceParserTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ksef.InvoiceParser

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
      refute Map.has_key?(attrs, :payment_method)

      # But due_date should be present
      assert attrs.due_date == ~D[2025-01-15]

      # Core fields present
      assert attrs.seller_nip == "1234567890"
      assert attrs.seller == "Test Seller"
      assert attrs.invoice_identifier == "TEST/001"
      assert Decimal.equal?(attrs.total_amount, Decimal.new("100.00"))
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
          </FaWiersz>
          <FaWiersz>
            <NrWierszaFa>2</NrWierszaFa>
            <P_7>Second item</P_7>
          </FaWiersz>
        </Fa>
      </Faktura>
      """

      assert {:ok, attrs} = InvoiceParser.parse(xml)

      # No payment fields
      refute Map.has_key?(attrs, :payment_method)
      refute Map.has_key?(attrs, :account_number)

      # Core fields work
      assert attrs.seller_nip == "9999999999"
      assert attrs.currency == "EUR"
      assert attrs.issue_date == ~D[2025-06-15]
      # sale_date defaults to issue_date when P_6 is missing
      assert attrs.sale_date == ~D[2025-06-15]
      assert Decimal.equal?(attrs.total_amount, Decimal.new("250.50"))
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
  end
end
