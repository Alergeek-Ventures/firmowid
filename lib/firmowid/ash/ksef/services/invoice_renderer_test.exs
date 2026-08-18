# credo:disable-for-this-file ExDNA.Credo
# This is a broad XSD conformance matrix with many near-identical scenario cases; collapsing
# it would reduce clarity/coverage and requires larger test architecture changes.
defmodule Firmowid.Ash.Ksef.Services.InvoiceRendererTest do
  @moduledoc """
  Tests for InvoiceRenderer.render_fa3/1 with XSD validation.

  These tests validate that rendered XML conforms to the official
  KSeF FA(3) XSD schema (schemat.xsd).
  """

  use Firmowid.DataCase, async: false

  import Firmowid.Ash.Ksef.KsefTestHelpers

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Ksef.Services.InvoiceRenderer

  # authorize?: false bypasses policies, actor: %{} satisfies require_actor? true
  # on domains like Invoicing.
  @bridge_opts [authorize?: false, actor: %{}]

  @moduletag :ksef_xsd

  setup_all do
    ensure_schemas_cached!()
    model = compile_ksef_schema!()
    %{model: model}
  end

  setup do
    user = Firmowid.AccountsFixtures.user_fixture()
    %{org_id: user.organization_id}
  end

  # ---------------------------------------------------------------------------
  # Domestic VAT Invoices
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - domestic VAT invoices" do
    test "23% VAT invoice passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(vat_rate: "23", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "8% VAT invoice passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(vat_rate: "8", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "5% VAT invoice passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(vat_rate: "5", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "multi-rate invoice (23%, 8%, 5%) passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_multi_rate_invoice(org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "0% domestic rate (0 KR) passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(vat_rate: "0 KR", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "company buyer name prefers the full legal name over display name", %{
      model: model,
      org_id: org_id
    } do
      invoice = build_domestic_invoice(org_id: org_id)

      invoice =
        Ash.Seed.update!(invoice, %{
          buyer_full_name: "Buyer Full Legal Name Sp. z o.o.",
          buyer_display_name: "Buyer Short Label"
        })

      xml = InvoiceRenderer.render_fa3(invoice)
      [buyer_section] = Regex.run(~r/<Podmiot2>.*?<\/Podmiot2>/s, xml, capture: :first)

      assert buyer_section =~ "<Nazwa>Buyer Full Legal Name Sp. z o.o.</Nazwa>"
      refute buyer_section =~ "<Nazwa>Buyer Short Label</Nazwa>"
      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # Reverse Charge Invoices
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - reverse charge invoices" do
    test "EU B2B reverse charge invoice passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_reverse_charge_invoice(org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "reverse charge with EUR currency passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_reverse_charge_invoice(currency: "EUR", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "reverse charge with USD currency passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_reverse_charge_invoice(currency: "USD", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "reverse charge with PLN currency passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_reverse_charge_invoice(currency: "PLN", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # Buyer Identification Types
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - buyer identification types" do
    test "Polish NIP buyer passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(buyer_id: :nip, org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "EU VAT buyer (KodUE + NrVatUE) passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_eu_vat_invoice(org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "other ID buyer (non-EU with NrID) passes XSD validation", %{
      model: model,
      org_id: org_id
    } do
      invoice = build_other_id_invoice(org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "no ID buyer (BrakID=1) passes XSD validation", %{model: model, org_id: org_id} do
      invoice = build_no_id_invoice(org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # Correction Invoices (KOR)
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - correction invoices" do
    test "KOR invoice with KSeF number passes XSD validation", %{model: model, org_id: org_id} do
      original =
        simulate_ksef_submission(build_domestic_invoice(org_id: org_id), with_ksef_number: true)

      correction = build_correction_invoice(original)
      xml = InvoiceRenderer.render_fa3(correction)

      assert :ok = validate_xml(xml, model)
    end

    test "KOR for reverse charge invoice passes XSD validation", %{model: model, org_id: org_id} do
      original =
        simulate_ksef_submission(build_reverse_charge_invoice(org_id: org_id),
          with_ksef_number: true
        )

      correction = build_correction_invoice(original)
      xml = InvoiceRenderer.render_fa3(correction)

      assert :ok = validate_xml(xml, model)
    end

    test "cancellation correction (zeroed items) passes XSD validation", %{
      model: model,
      org_id: org_id
    } do
      original =
        simulate_ksef_submission(build_domestic_invoice(org_id: org_id), with_ksef_number: true)

      opts = Keyword.put(@bridge_opts, :tenant, original.organization_id)

      cancellation =
        original.id
        |> SalesInvoice.cancel!(opts)
        |> Ash.load!([:sales_invoice_items, corrected_invoice: :sales_invoice_items], opts)

      xml = InvoiceRenderer.render_fa3(cancellation)

      assert :ok = validate_xml(xml, model)

      # should include before+after rows for changed items
      assert length(Regex.scan(~r/<FaWiersz>/, xml)) >= 2
      assert xml =~ "<P_8B>0</P_8B>"
    end
  end

  # ---------------------------------------------------------------------------
  # Edge Cases
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - edge cases" do
    test "XML special characters in buyer name are properly escaped", %{
      model: model,
      org_id: org_id
    } do
      invoice = build_domestic_invoice(buyer_name: "Test & Co <Corp> \"Ltd\"", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      # Verify escaping in raw XML
      assert xml =~ "&amp;"
      assert xml =~ "&lt;"
      assert xml =~ "&gt;"
      assert xml =~ "&quot;"

      assert :ok = validate_xml(xml, model)
    end

    test "XML special characters in item name are properly escaped", %{
      model: model,
      org_id: org_id
    } do
      invoice = build_domestic_invoice(item_name: "Service's 'special' <deal>", org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert :ok = validate_xml(xml, model)
    end

    test "large quantities use normal notation (no scientific)", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(quantity: Decimal.new("100"), org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      # Verify format in raw XML - should not be scientific notation
      refute xml =~ "1E+2"
      refute xml =~ "1e+2"
      assert xml =~ ">100<"

      assert :ok = validate_xml(xml, model)
    end

    test "very large quantities are formatted correctly", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(quantity: Decimal.new("1000000"), org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      # Should not be 1E+6
      refute xml =~ ~r/\d[eE]\+\d/
      assert xml =~ ">1000000<"

      assert :ok = validate_xml(xml, model)
    end

    test "fractional quantities are formatted correctly", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(quantity: Decimal.new("0.5"), org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert xml =~ ">0.5<"
      assert :ok = validate_xml(xml, model)
    end

    test "optional sale_date can be omitted", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(sale_date: nil, org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      # P_6 element should not be present
      refute xml =~ "<P_6>"

      assert :ok = validate_xml(xml, model)
    end

    test "optional buyer_address can be omitted", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(buyer_address: nil, org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      # Buyer Address section should not be present
      # The pattern looks for Adres within Podmiot2
      refute xml =~ ~r/<Podmiot2>.*<Adres>.*<AdresL1>/s

      assert :ok = validate_xml(xml, model)
    end

    test "multiple line items are valid", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(items: 5, org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      # Should have 5 FaWiersz elements
      assert length(Regex.scan(~r/<FaWiersz>/, xml)) == 5

      assert :ok = validate_xml(xml, model)
    end

    test "invoice with 10 line items is valid", %{model: model, org_id: org_id} do
      invoice = build_domestic_invoice(items: 10, org_id: org_id)
      xml = InvoiceRenderer.render_fa3(invoice)

      assert length(Regex.scan(~r/<FaWiersz>/, xml)) == 10
      assert :ok = validate_xml(xml, model)
    end
  end

  # ---------------------------------------------------------------------------
  # FA(3) Example Fixtures (Filtered)
  # ---------------------------------------------------------------------------

  describe "render_fa3/1 - FA(3) example fixtures" do
    test "example 2 correction invoice matches fixture (normalized)", %{
      model: model,
      org_id: org_id
    } do
      original = build_example_2_original(org_id)
      original = update_ksef_submission(original, "9999999999-20230908-8BEF280C8D35-4D")

      correction = build_example_2_correction(original)
      xml = InvoiceRenderer.render_fa3(correction)

      assert :ok = validate_xml(xml, model)

      expected = load_example_fixture("FA_3_Przykład_2.xml")

      assert normalize_fa3(xml) == normalize_fa3(expected)
    end

    test "example 5 correction invoice matches fixture (normalized)", %{
      model: model,
      org_id: org_id
    } do
      original = build_example_5_original(org_id)
      original = update_ksef_submission(original, "9999999999-20230908-8BEF280C8D35-4D")

      correction = build_example_5_correction(original)
      xml = InvoiceRenderer.render_fa3(correction)

      assert :ok = validate_xml(xml, model)

      expected = load_example_fixture("FA_3_Przykład_5.xml")

      assert normalize_fa3(xml) == normalize_fa3(expected)
    end
  end

  defp build_example_2_original(org_id) do
    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "FV2026/02/150",
        issue_date: ~D[2026-02-15],
        sale_date: ~D[2026-01-27],
        due_date: nil,
        currency: "PLN",
        payment_method: :transfer,
        seller_nip: "9999999999",
        seller_display_name: "ABC AGD sp. z o. o.",
        seller_address: "ul. Kwiatowa 1 m. 2",
        seller_account_number: nil,
        buyer_type: :company,
        buyer_id: "1111111111",
        buyer_full_name: "F.H.U. Jan Kowalski",
        buyer_address: "ul. Polna 1",
        buyer_country: "PL",
        is_reverse_charge: false,
        ksef_invoice_kind: :vat,
        invoice_type: :poland,
        organization_id: org_id
      })

    Ash.Seed.seed!(SalesInvoiceItem, %{
      name: "lodówka Zimnotech mk1",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("1626.01"),
      vat_rate: "23",
      sales_invoice_id: invoice.id,
      organization_id: invoice.organization_id,
      index: 0
    })

    Ash.load!(
      invoice,
      [:sales_invoice_items],
      Keyword.put(@bridge_opts, :tenant, invoice.organization_id)
    )
  end

  defp build_example_2_correction(original) do
    correction =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "FK2026/03/200",
        issue_date: ~D[2026-03-15],
        sale_date: ~D[2026-01-27],
        due_date: nil,
        correction_reason: "obniżka ceny o 200 zł z uwagi na uszkodzenia estetyczne",
        ksef_invoice_kind: :kor,
        corrected_invoice_id: original.id,
        invoice_type: original.invoice_type,
        currency: original.currency,
        payment_method: original.payment_method,
        seller_nip: original.seller_nip,
        seller_display_name: original.seller_display_name,
        seller_address: original.seller_address,
        seller_account_number: original.seller_account_number,
        buyer_type: original.buyer_type,
        buyer_id: original.buyer_id,
        buyer_full_name: original.buyer_full_name,
        buyer_address: original.buyer_address,
        buyer_country: original.buyer_country,
        is_reverse_charge: original.is_reverse_charge,
        organization_id: original.organization_id
      })

    Ash.Seed.seed!(SalesInvoiceItem, %{
      name: "lodówka Zimnotech mk1",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("1463.41"),
      vat_rate: "23",
      sales_invoice_id: correction.id,
      organization_id: correction.organization_id,
      index: 0
    })

    Ash.load!(
      correction,
      [:sales_invoice_items, :corrected_invoice],
      Keyword.put(@bridge_opts, :tenant, correction.organization_id)
    )
  end

  defp build_example_5_original(org_id) do
    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "FV2026/02/150",
        issue_date: ~D[2026-02-15],
        sale_date: nil,
        due_date: nil,
        currency: "PLN",
        payment_method: :transfer,
        seller_nip: "9999999999",
        seller_display_name: "ABC AGD sp. z o. o.",
        seller_address: "ul. Kwiatowa 1 m. 2",
        seller_account_number: nil,
        buyer_type: :company,
        buyer_id: "1111111111",
        buyer_full_name: "CDE sp. j.",
        buyer_address: "ul. Sadowa 1 lok. 3",
        buyer_country: "PL",
        is_reverse_charge: false,
        ksef_invoice_kind: :vat,
        invoice_type: :poland,
        organization_id: org_id
      })

    Ash.Seed.seed!(SalesInvoiceItem, %{
      name: "Usluga programistyczna",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("100.00"),
      vat_rate: "23",
      sales_invoice_id: invoice.id,
      organization_id: invoice.organization_id,
      index: 0
    })

    Ash.load!(
      invoice,
      [:sales_invoice_items],
      Keyword.put(@bridge_opts, :tenant, invoice.organization_id)
    )
  end

  defp update_ksef_submission(invoice, ksef_number) do
    Ash.Seed.update!(invoice, %{locked_at: DateTime.utc_now(), ksef_number: ksef_number})
  end

  defp build_example_5_correction(original) do
    correction =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "FK2026/04/23",
        issue_date: ~D[2026-04-01],
        sale_date: nil,
        due_date: nil,
        correction_reason: "błędna nazwa nabywcy",
        ksef_invoice_kind: :kor,
        corrected_invoice_id: original.id,
        invoice_type: original.invoice_type,
        currency: original.currency,
        payment_method: original.payment_method,
        seller_nip: original.seller_nip,
        seller_display_name: original.seller_display_name,
        seller_address: original.seller_address,
        seller_account_number: original.seller_account_number,
        buyer_type: original.buyer_type,
        buyer_id: original.buyer_id,
        buyer_full_name: "CeDeE s.c.",
        buyer_address: original.buyer_address,
        buyer_country: original.buyer_country,
        is_reverse_charge: original.is_reverse_charge,
        organization_id: original.organization_id
      })

    Ash.Seed.seed!(SalesInvoiceItem, %{
      name: "Usluga programistyczna",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("100.00"),
      vat_rate: "23",
      sales_invoice_id: correction.id,
      organization_id: correction.organization_id,
      index: 0
    })

    Ash.load!(
      correction,
      [:sales_invoice_items, :corrected_invoice],
      Keyword.put(@bridge_opts, :tenant, correction.organization_id)
    )
  end

  defp load_example_fixture(name) do
    ["lib", "test", "fixtures", "ksef", "fa3_examples", name]
    |> Path.join()
    |> File.read!()
  end

  defp normalize_fa3(xml) do
    xml
    |> strip_ignored_elements()
    |> strip_prefixed_namespaces()
    |> strip_root_namespace_attrs()
    |> String.replace(["\r", "\n", "\t"], "")
    |> strip_tag_padding()
    |> strip_trailing_zero_decimals()
  end

  defp strip_ignored_elements(xml) do
    ignored_tags = [
      "DataWytworzeniaFa",
      "SystemInfo",
      "DaneKontaktowe",
      "AdresL2",
      "NrKlienta",
      "IDNabywcy",
      "UU_ID",
      "P_1M",
      "TypKorekty",
      "Platnosc",
      "Stopka"
    ]

    Enum.reduce(ignored_tags, xml, fn tag, acc ->
      Regex.replace(~r/<#{tag}\b[^>]*>.*?<\/#{tag}>/s, acc, "")
    end)
  end

  defp strip_prefixed_namespaces(xml) do
    Regex.replace(~r/\s+xmlns:[a-zA-Z0-9]+="[^"]+"/, xml, "")
  end

  defp strip_root_namespace_attrs(xml) do
    Regex.replace(~r/<Faktura\b[^>]*>/, xml, "<Faktura>")
  end

  defp strip_tag_padding(xml) do
    xml
    |> then(&Regex.replace(~r/>\s+([^<])/, &1, ">\\1"))
    |> then(&Regex.replace(~r/([^>])\s+</, &1, "\\1<"))
    |> then(&Regex.replace(~r/>\s+</, &1, "><"))
    |> String.trim()
  end

  defp strip_trailing_zero_decimals(xml) do
    Regex.replace(~r/>(-?\d+\.\d+)</, xml, fn _full, number ->
      trimmed =
        number
        |> String.trim_trailing("0")
        |> String.trim_trailing(".")

      ">#{trimmed}<"
    end)
  end
end
