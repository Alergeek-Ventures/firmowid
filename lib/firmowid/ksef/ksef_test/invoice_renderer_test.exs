defmodule Firmowid.Ksef.InvoiceRendererTest do
  @moduledoc """
  Tests for InvoiceRenderer.render_fa3/1 with XSD validation.

  These tests validate that rendered XML conforms to the official
  KSeF FA(3) XSD schema (schemat.xsd).
  """

  use Firmowid.DataCase, async: false

  import Firmowid.KsefTestHelpers

  alias Firmowid.Ksef.InvoiceRenderer

  @moduletag :ksef_xsd

  setup_all do
    ensure_schemas_cached!()
    model = compile_ksef_schema!()
    %{model: model}
  end

  setup do
    Firmowid.AccountsFixtures.user_fixture()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Domestic VAT Invoices
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - domestic VAT invoices" do
    test "23% VAT invoice passes XSD validation", %{model: model} do
      invoice = build_domestic_invoice(vat_rate: 23)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "8% VAT invoice passes XSD validation", %{model: model} do
      invoice = build_domestic_invoice(vat_rate: 8)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "5% VAT invoice passes XSD validation", %{model: model} do
      invoice = build_domestic_invoice(vat_rate: 5)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "multi-rate invoice (23%, 8%, 5%) passes XSD validation", %{model: model} do
      invoice = build_multi_rate_invoice()
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "0% domestic rate (0 KR) passes XSD validation", %{model: model} do
      invoice = build_domestic_invoice(vat_rate: 0)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # Reverse Charge Invoices
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - reverse charge invoices" do
    test "EU B2B reverse charge invoice passes XSD validation", %{model: model} do
      invoice = build_reverse_charge_invoice()
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "reverse charge with EUR currency passes XSD validation", %{model: model} do
      invoice = build_reverse_charge_invoice(currency: "EUR")
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "reverse charge with USD currency passes XSD validation", %{model: model} do
      invoice = build_reverse_charge_invoice(currency: "USD")
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "reverse charge with PLN currency passes XSD validation", %{model: model} do
      invoice = build_reverse_charge_invoice(currency: "PLN")
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # Buyer Identification Types
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - buyer identification types" do
    test "Polish NIP buyer passes XSD validation", %{model: model} do
      invoice = build_domestic_invoice(buyer_id: :nip)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "EU VAT buyer (KodUE + NrVatUE) passes XSD validation", %{model: model} do
      invoice = build_eu_vat_invoice()
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "other ID buyer (non-EU with NrID) passes XSD validation", %{model: model} do
      invoice = build_other_id_invoice()
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "no ID buyer (BrakID=1) passes XSD validation", %{model: model} do
      invoice = build_no_id_invoice()
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # Correction Invoices (KOR)
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - correction invoices" do
    test "KOR invoice with KSeF number passes XSD validation", %{model: model} do
      original = simulate_ksef_submission(build_domestic_invoice(), with_ksef_number: true)

      correction = build_correction_invoice(original)
      xml = InvoiceRenderer.render_fa3(correction)

      assert :ok = validate_xml(xml, model)
    end

    test "KOR for reverse charge invoice passes XSD validation", %{model: model} do
      original = simulate_ksef_submission(build_reverse_charge_invoice(), with_ksef_number: true)

      correction = build_correction_invoice(original)
      xml = InvoiceRenderer.render_fa3(correction)

      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # Edge Cases
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - edge cases" do
    test "XML special characters in buyer name are properly escaped", %{model: model} do
      invoice = build_domestic_invoice(buyer_name: "Test & Co <Corp> \"Ltd\"")
      xml = InvoiceRenderer.render_fa3(invoice)

      # Verify escaping in raw XML
      assert xml =~ "&amp;"
      assert xml =~ "&lt;"
      assert xml =~ "&gt;"
      assert xml =~ "&quot;"

      assert :ok = validate_xml(xml, model)
    end

    test "XML special characters in item name are properly escaped", %{model: model} do
      invoice = build_domestic_invoice(item_name: "Service's 'special' <deal>")
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "large quantities use normal notation (no scientific)", %{model: model} do
      invoice = build_domestic_invoice(quantity: Decimal.new("100"))
      xml = InvoiceRenderer.render_fa3(invoice)

      # Verify format in raw XML - should not be scientific notation
      refute xml =~ "1E+2"
      refute xml =~ "1e+2"
      assert xml =~ ">100<"

      assert :ok = validate_xml(xml, model)
    end

    test "very large quantities are formatted correctly", %{model: model} do
      invoice = build_domestic_invoice(quantity: Decimal.new("1000000"))
      xml = InvoiceRenderer.render_fa3(invoice)

      # Should not be 1E+6
      refute xml =~ ~r/\d[eE]\+\d/
      assert xml =~ ">1000000<"

      assert :ok = validate_xml(xml, model)
    end

    test "fractional quantities are formatted correctly", %{model: model} do
      invoice = build_domestic_invoice(quantity: Decimal.new("0.5"))
      xml = InvoiceRenderer.render_fa3(invoice)

      assert xml =~ ">0.5<"
      assert :ok = validate_xml(xml, model)
    end

    test "optional sale_date can be omitted", %{model: model} do
      invoice = build_domestic_invoice(sale_date: nil)
      xml = InvoiceRenderer.render_fa3(invoice)

      # P_6 element should not be present
      refute xml =~ "<P_6>"

      assert :ok = validate_xml(xml, model)
    end

    test "optional buyer_address can be omitted", %{model: model} do
      invoice = build_domestic_invoice(buyer_address: nil)
      xml = InvoiceRenderer.render_fa3(invoice)

      # Buyer Address section should not be present
      # The pattern looks for Adres within Podmiot2
      refute xml =~ ~r/<Podmiot2>.*<Adres>.*<AdresL1>/s

      assert :ok = validate_xml(xml, model)
    end

    test "multiple line items are valid", %{model: model} do
      invoice = build_domestic_invoice(items: 5)
      xml = InvoiceRenderer.render_fa3(invoice)

      # Should have 5 FaWiersz elements
      assert length(Regex.scan(~r/<FaWiersz>/, xml)) == 5

      assert :ok = validate_xml(xml, model)
    end

    test "invoice with 10 line items is valid", %{model: model} do
      invoice = build_domestic_invoice(items: 10)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert length(Regex.scan(~r/<FaWiersz>/, xml)) == 10
      assert :ok = validate_xml(xml, model)
    end
  end
end
