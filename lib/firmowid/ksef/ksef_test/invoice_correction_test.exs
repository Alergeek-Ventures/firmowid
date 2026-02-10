defmodule Firmowid.Ksef.InvoiceCorrectionTest do
  @moduledoc """
  Tests for correction invoice chain behavior in KSeF XML rendering.

  Validates that:
  - DaneFaKorygowanej always references the original (primary) invoice
  - P_15 gross delta is computed against the reference invoice (previous correction)
  - StanPrzed line items come from the reference invoice, not the original
  - Podmiot2K buyer data comes from the reference invoice
  - Validation guards raise on buyer tax ID or seller data changes
  """

  use Firmowid.DataCase, async: false

  import Firmowid.KsefTestHelpers
  import SweetXml

  alias Firmowid.Ksef.InvoiceRenderer

  setup do
    Firmowid.AccountsFixtures.user_fixture()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Creates an original invoice with the given items and buyer name.
  defp build_original(opts \\ []) do
    item_price = Keyword.get(opts, :unit_price, "100.00")
    item_name = Keyword.get(opts, :item_name, "Original Service")
    buyer_name = Keyword.get(opts, :buyer_name, "Test Buyer S.A.")

    [vat_rate: "23", buyer_name: buyer_name, item_name: item_name, quantity: Decimal.new("1")]
    |> build_domestic_invoice()
    |> then(fn invoice ->
      # Update unit_price if non-default (build_domestic_invoice always uses 100.00)
      if item_price == "100.00" do
        invoice
      else
        update_item_prices(invoice, item_price)
      end
    end)
  end

  # Submits an invoice to KSeF (locks it and assigns a KSeF number).
  # Uses an incrementing timestamp to ensure distinct locked_at values,
  # since the field is :utc_datetime (second precision).
  defp submit(invoice, locked_at \\ nil) do
    locked_at = locked_at || DateTime.utc_now()

    ksef_hex = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :upper)

    ksef_number =
      "1234567890-20260115-#{String.slice(ksef_hex, 0, 6)}-#{String.slice(ksef_hex, 6, 6)}-#{String.slice(ksef_hex, 12, 2)}"

    {:ok, updated} =
      invoice
      |> Firmowid.SalesInvoices.SalesInvoice.ksef_update_changeset(%{
        locked_at: locked_at,
        ksef_number: ksef_number
      })
      |> Firmowid.Repo.update()

    updated
  end

  # Creates a correction invoice with distinct item data.
  defp correct(original, opts \\ []) do
    item_price = Keyword.get(opts, :unit_price, "150.00")
    item_name = Keyword.get(opts, :item_name, "Corrected Service")
    buyer_name = Keyword.get(opts, :buyer_name, nil)

    items = [
      %{
        name: item_name,
        quantity: Decimal.new("1"),
        unit: "szt.",
        unit_price: Decimal.new(item_price),
        vat_rate: "23"
      }
    ]

    attrs =
      maybe_put(
        %{
          invoice_number: unique_invoice_number("KOR/"),
          issue_date: ~D[2026-01-20],
          sale_date: ~D[2026-01-15],
          due_date: ~D[2026-02-05],
          payment_method: original.payment_method,
          sales_invoice_items: items
        },
        :buyer_full_name,
        buyer_name
      )

    {:ok, correction} = Firmowid.SalesInvoices.create_correction_invoice(original, attrs)
    Firmowid.Repo.preload(correction, [:sales_invoice_items, :corrected_invoice])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Updates all item prices on an invoice via direct DB update.
  defp update_item_prices(invoice, price) do
    for item <- invoice.sales_invoice_items do
      item
      |> Ecto.Changeset.change(%{unit_price: Decimal.new(price)})
      |> Firmowid.Repo.update!()
    end

    Firmowid.Repo.preload(invoice, :sales_invoice_items, force: true)
  end

  # Renders FA3 XML and parses it for assertions.
  defp render_xml(invoice) do
    invoice
    |> InvoiceRenderer.render_fa3()
    |> IO.iodata_to_binary()
  end

  # Calculates expected gross for 1 item at the given price with 23% VAT.
  # gross = price * 1 * 1.23, rounded to 2 decimal places.
  defp expected_gross(price_str) do
    price_str
    |> Decimal.new()
    |> Decimal.mult(Decimal.new("1.23"))
    |> Decimal.round(2)
  end

  # ---------------------------------------------------------------------------
  # Correction chain builder
  # ---------------------------------------------------------------------------

  # Builds a chain: original -> KOR1 -> KOR2 -> KOR3 with distinct data at each level.
  # Returns {original, kor1, kor2, kor3}.
  defp build_correction_chain do
    # Use explicit timestamps with 1-second gaps to ensure distinct ordering.
    # locked_at is :utc_datetime (second precision), so sub-second gaps don't work.
    t0 = ~U[2026-01-15 10:00:00Z]
    t1 = ~U[2026-01-15 10:00:01Z]
    t2 = ~U[2026-01-15 10:00:02Z]

    original = build_original(item_name: "Original Service", unit_price: "100.00")
    original = submit(original, t0)

    kor1 = correct(original, item_name: "Corrected Service v1", unit_price: "150.00")
    kor1 = submit(kor1, t1)

    kor2 = correct(original, item_name: "Corrected Service v2", unit_price: "200.00")
    kor2 = submit(kor2, t2)

    kor3 = correct(original, item_name: "Corrected Service v3", unit_price: "250.00")

    {original, kor1, kor2, kor3}
  end

  # ---------------------------------------------------------------------------
  # DaneFaKorygowanej — always references the original invoice
  # ---------------------------------------------------------------------------

  describe "DaneFaKorygowanej always references the original invoice" do
    test "first correction references the original" do
      original = submit(build_original())
      kor1 = correct(original)

      xml = render_xml(kor1)
      doc = parse(xml)

      assert xpath(doc, ~x"//DaneFaKorygowanej/NrFaKorygowanej/text()"s) == original.invoice_number
      assert xpath(doc, ~x"//DaneFaKorygowanej/DataWystFaKorygowanej/text()"s) == Date.to_iso8601(original.issue_date)
      assert xpath(doc, ~x"//DaneFaKorygowanej/NrKSeFFaKorygowanej/text()"s) == original.ksef_number
    end

    test "second correction in chain still references the original, not KOR1" do
      {original, _kor1, kor2, _kor3} = build_correction_chain()

      xml = render_xml(kor2)
      doc = parse(xml)

      assert xpath(doc, ~x"//DaneFaKorygowanej/NrFaKorygowanej/text()"s) == original.invoice_number
      assert xpath(doc, ~x"//DaneFaKorygowanej/DataWystFaKorygowanej/text()"s) == Date.to_iso8601(original.issue_date)
    end

    test "third correction in chain still references the original" do
      {original, _kor1, _kor2, kor3} = build_correction_chain()

      xml = render_xml(kor3)
      doc = parse(xml)

      assert xpath(doc, ~x"//DaneFaKorygowanej/NrFaKorygowanej/text()"s) == original.invoice_number
      assert xpath(doc, ~x"//DaneFaKorygowanej/DataWystFaKorygowanej/text()"s) == Date.to_iso8601(original.issue_date)
    end
  end

  # ---------------------------------------------------------------------------
  # P_15 gross delta — computed against the reference invoice
  # ---------------------------------------------------------------------------

  describe "P_15 gross delta uses reference invoice" do
    test "first correction: delta = KOR1.gross - original.gross" do
      original = [unit_price: "100.00"] |> build_original() |> submit()
      kor1 = correct(original, unit_price: "150.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      p15 = doc |> xpath(~x"//Fa/P_15/text()"s) |> Decimal.new()
      expected = Decimal.sub(expected_gross("150.00"), expected_gross("100.00"))

      assert Decimal.eq?(p15, expected),
             "P_15 should be #{expected} but got #{p15}"
    end

    test "second correction: delta = KOR2.gross - KOR1.gross (not original)" do
      {_original, _kor1, kor2, _kor3} = build_correction_chain()

      xml = render_xml(kor2)
      doc = parse(xml)

      p15 = doc |> xpath(~x"//Fa/P_15/text()"s) |> Decimal.new()

      # KOR2 price=200, KOR1 price=150 → delta = (200*1.23) - (150*1.23) = 246 - 184.50 = 61.50
      expected = Decimal.sub(expected_gross("200.00"), expected_gross("150.00"))

      assert Decimal.eq?(p15, expected),
             "P_15 should be #{expected} (KOR2 - KOR1) but got #{p15}"
    end

    test "third correction: delta = KOR3.gross - KOR2.gross" do
      {_original, _kor1, _kor2, kor3} = build_correction_chain()

      xml = render_xml(kor3)
      doc = parse(xml)

      p15 = doc |> xpath(~x"//Fa/P_15/text()"s) |> Decimal.new()

      # KOR3 price=250, KOR2 price=200 → delta = (250*1.23) - (200*1.23) = 307.50 - 246 = 61.50
      expected = Decimal.sub(expected_gross("250.00"), expected_gross("200.00"))

      assert Decimal.eq?(p15, expected),
             "P_15 should be #{expected} (KOR3 - KOR2) but got #{p15}"
    end

    test "correction that reduces price yields negative P_15" do
      original = [unit_price: "200.00"] |> build_original() |> submit()
      kor1 = correct(original, unit_price: "50.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      p15 = doc |> xpath(~x"//Fa/P_15/text()"s) |> Decimal.new()
      expected = Decimal.sub(expected_gross("50.00"), expected_gross("200.00"))

      assert Decimal.negative?(expected)

      assert Decimal.eq?(p15, expected),
             "P_15 should be negative #{expected} but got #{p15}"
    end
  end

  # ---------------------------------------------------------------------------
  # StanPrzed / FaWiersz — "before" items from reference invoice
  # ---------------------------------------------------------------------------

  describe "StanPrzed line items use reference invoice" do
    test "first correction: before items come from original" do
      original = [item_name: "Original Service", unit_price: "100.00"] |> build_original() |> submit()
      kor1 = correct(original, item_name: "Corrected Service v1", unit_price: "150.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      # FaWiersz with StanPrzed=1 are "before" rows
      before_names = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_7/text()"ls)
      before_prices = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_9A/text()"ls)

      assert before_names == ["Original Service"]
      assert before_prices == ["100.00"]

      # FaWiersz without StanPrzed are "after" rows
      after_names = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_7/text()"ls)
      after_prices = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_9A/text()"ls)

      assert after_names == ["Corrected Service v1"]
      assert after_prices == ["150.00"]
    end

    test "second correction: before items come from KOR1, not original" do
      {_original, _kor1, kor2, _kor3} = build_correction_chain()

      xml = render_xml(kor2)
      doc = parse(xml)

      before_names = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_7/text()"ls)
      before_prices = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_9A/text()"ls)

      # Before state should be KOR1's data, not the original's
      assert before_names == ["Corrected Service v1"]
      assert before_prices == ["150.00"]

      after_names = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_7/text()"ls)
      assert after_names == ["Corrected Service v2"]
    end

    test "third correction: before items come from KOR2" do
      {_original, _kor1, _kor2, kor3} = build_correction_chain()

      xml = render_xml(kor3)
      doc = parse(xml)

      before_names = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_7/text()"ls)
      before_prices = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_9A/text()"ls)

      assert before_names == ["Corrected Service v2"]
      assert before_prices == ["200.00"]

      after_names = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_7/text()"ls)
      assert after_names == ["Corrected Service v3"]
    end

    test "before and after row counts match their respective invoices" do
      original =
        [vat_rate: "23", items: 3, item_name: "Multi Item"]
        |> build_domestic_invoice()
        |> submit()

      kor1 =
        correct(original,
          item_name: "Single Corrected",
          unit_price: "500.00"
        )

      xml = render_xml(kor1)
      doc = parse(xml)

      before_rows = xpath(doc, ~x"//FaWiersz[StanPrzed='1']"l)
      after_rows = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]"l)

      # Original had 3 items, correction has 1 item
      assert length(before_rows) == 3
      assert length(after_rows) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # FaWiersz conditional rendering — only when items changed
  # ---------------------------------------------------------------------------

  describe "FaWiersz conditional rendering" do
    test "buyer-only correction: no FaWiersz rendered" do
      original =
        [item_name: "Original Service", unit_price: "100.00"]
        |> build_original()
        |> submit()

      # Create correction with identical items (name, quantity, unit, price, vat_rate)
      kor1 =
        correct(original,
          item_name: "Original Service",
          unit_price: "100.00",
          buyer_name: "Updated Buyer Corp."
        )

      xml = render_xml(kor1)
      doc = parse(xml)

      # No FaWiersz should be present because items are identical
      fawiersz = xpath(doc, ~x"//FaWiersz"l)
      assert Enum.empty?(fawiersz)

      # Podmiot2K should still be present because buyer name changed
      podmiot2k_name = xpath(doc, ~x"//Podmiot2K/DaneIdentyfikacyjne/Nazwa/text()"s)
      assert podmiot2k_name == "Test Buyer S.A."
    end

    test "item name change: FaWiersz rendered" do
      original =
        [item_name: "Original Service", unit_price: "100.00"]
        |> build_original()
        |> submit()

      kor1 = correct(original, item_name: "Updated Service", unit_price: "100.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      # Both before and after FaWiersz should be present
      before_names = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_7/text()"ls)
      after_names = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_7/text()"ls)

      assert before_names == ["Original Service"]
      assert after_names == ["Updated Service"]
    end

    test "unit_price change: FaWiersz rendered" do
      original =
        [item_name: "Service", unit_price: "100.00"]
        |> build_original()
        |> submit()

      kor1 = correct(original, item_name: "Service", unit_price: "200.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      before_prices = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_9A/text()"ls)
      after_prices = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_9A/text()"ls)

      assert before_prices == ["100.00"]
      assert after_prices == ["200.00"]
    end

    test "vat_rate change: FaWiersz rendered" do
      original =
        [item_name: "Service", unit_price: "100.00", vat_rate: "23"]
        |> build_domestic_invoice()
        |> submit()

      # Change VAT rate from 23% to 8%
      kor1 =
        original
        |> correct(
          item_name: "Service",
          unit_price: "100.00"
        )
        |> then(fn kor ->
          # Update VAT rate to 8% after creation
          [item] = kor.sales_invoice_items

          item
          |> Ecto.Changeset.change(%{vat_rate: "8"})
          |> Repo.update!()

          Repo.preload(kor, :sales_invoice_items, force: true)
        end)

      xml = render_xml(kor1)
      doc = parse(xml)

      before_vat = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_12/text()"ls)
      after_vat = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_12/text()"ls)

      assert before_vat == ["23"]
      assert after_vat == ["8"]
    end

    test "quantity change: FaWiersz rendered" do
      original =
        [item_name: "Service", unit_price: "100.00", quantity: Decimal.new("1")]
        |> build_domestic_invoice()
        |> submit()

      # Change quantity from 1 to 2
      kor1 =
        original
        |> correct(
          item_name: "Service",
          unit_price: "100.00"
        )
        |> then(fn kor ->
          [item] = kor.sales_invoice_items

          item
          |> Ecto.Changeset.change(%{quantity: Decimal.new("2")})
          |> Repo.update!()

          Repo.preload(kor, :sales_invoice_items, force: true)
        end)

      xml = render_xml(kor1)
      doc = parse(xml)

      before_qty = xpath(doc, ~x"//FaWiersz[StanPrzed='1']/P_8B/text()"ls)
      after_qty = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]/P_8B/text()"ls)

      assert before_qty == ["1"]
      assert after_qty == ["2"]
    end

    test "item count change: FaWiersz rendered" do
      original = submit(build_original(item_name: "Single Item", unit_price: "100.00"))

      # Correction with 2 items instead of 1
      kor1 =
        original
        |> correct(
          item_name: "Item A",
          unit_price: "100.00"
        )
        |> then(fn kor ->
          {:ok, updated} =
            Firmowid.SalesInvoices.update_sales_invoice(kor, %{
              sales_invoice_items: [
                %{
                  name: "Item A",
                  quantity: Decimal.new("1"),
                  unit: "szt.",
                  unit_price: Decimal.new("100.00"),
                  vat_rate: "23"
                },
                %{
                  name: "Item B",
                  quantity: Decimal.new("1"),
                  unit: "szt.",
                  unit_price: Decimal.new("50.00"),
                  vat_rate: "23"
                }
              ]
            })

          Repo.preload(updated, [:sales_invoice_items, :corrected_invoice])
        end)

      xml = render_xml(kor1)
      doc = parse(xml)

      before_rows = xpath(doc, ~x"//FaWiersz[StanPrzed='1']"l)
      after_rows = xpath(doc, ~x"//FaWiersz[not(StanPrzed)]"l)

      assert length(before_rows) == 1
      assert length(after_rows) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Podmiot2K — buyer data from reference invoice
  # ---------------------------------------------------------------------------

  describe "Podmiot2K uses reference invoice buyer data" do
    test "buyer change in first correction: Podmiot2K shows original buyer" do
      original =
        [vat_rate: "23", buyer_name: "Original Buyer Corp."]
        |> build_domestic_invoice()
        |> submit()

      kor1 = correct(original, buyer_name: "Updated Buyer Corp.", unit_price: "100.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      # Podmiot2K should be present because buyer name changed
      podmiot2k_name = xpath(doc, ~x"//Podmiot2K/DaneIdentyfikacyjne/Nazwa/text()"s)
      assert podmiot2k_name == "Original Buyer Corp."

      # Current buyer (Podmiot2) should have the new name
      podmiot2_name = xpath(doc, ~x"//Podmiot2/DaneIdentyfikacyjne/Nazwa/text()"s)
      assert podmiot2_name == "Updated Buyer Corp."
    end

    test "buyer change in second correction: Podmiot2K shows KOR1 buyer, not original" do
      original =
        [vat_rate: "23", buyer_name: "Original Buyer Corp."]
        |> build_domestic_invoice()
        |> submit()

      _kor1 = original |> correct(buyer_name: "Updated Buyer v1", unit_price: "150.00") |> submit()
      kor2 = correct(original, buyer_name: "Updated Buyer v2", unit_price: "200.00")

      xml = render_xml(kor2)
      doc = parse(xml)

      # Podmiot2K should show KOR1's buyer name (the reference), not the original's
      podmiot2k_name = xpath(doc, ~x"//Podmiot2K/DaneIdentyfikacyjne/Nazwa/text()"s)
      assert podmiot2k_name == "Updated Buyer v1"

      podmiot2_name = xpath(doc, ~x"//Podmiot2/DaneIdentyfikacyjne/Nazwa/text()"s)
      assert podmiot2_name == "Updated Buyer v2"
    end

    test "no buyer change: Podmiot2K is absent" do
      original = submit(build_original())
      kor1 = correct(original, unit_price: "150.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      # Buyer data didn't change, so Podmiot2K should not appear
      podmiot2k = xpath(doc, ~x"//Podmiot2K"o)
      assert is_nil(podmiot2k)
    end

    test "buyer address change triggers Podmiot2K with reference address" do
      original =
        [vat_rate: "23", buyer_address: "ul. Stara 1, 00-001 Warszawa"]
        |> build_domestic_invoice()
        |> submit()

      kor1 =
        original
        |> correct(unit_price: "100.00")
        |> then(fn kor ->
          {:ok, updated} =
            Firmowid.SalesInvoices.update_sales_invoice(kor, %{
              buyer_address: "ul. Nowa 99, 00-002 Krakow"
            })

          Firmowid.Repo.preload(updated, [:sales_invoice_items, :corrected_invoice])
        end)

      xml = render_xml(kor1)
      doc = parse(xml)

      podmiot2k_address = xpath(doc, ~x"//Podmiot2K/Adres/AdresL1/text()"s)
      assert podmiot2k_address == "ul. Stara 1, 00-001 Warszawa"
    end
  end

  # ---------------------------------------------------------------------------
  # Validation guards
  # ---------------------------------------------------------------------------

  describe "validation guards" do
    test "raises when buyer tax ID changes between correction and original" do
      original = submit(build_original())
      kor1 = correct(original, unit_price: "150.00")

      # Directly modify the buyer_id to simulate a tax ID change
      kor1_with_changed_id =
        kor1
        |> Firmowid.Repo.preload(corrected_invoice: :sales_invoice_items)
        |> Map.put(:buyer_id, "1111111111")

      assert_raise RuntimeError, ~r/Buyer tax ID cannot change/, fn ->
        InvoiceRenderer.render_fa3(kor1_with_changed_id)
      end
    end

    test "raises when seller data changes between correction and original" do
      original = submit(build_original())
      kor1 = correct(original, unit_price: "150.00")

      # Directly modify seller data to simulate a change
      kor1_with_changed_seller =
        kor1
        |> Firmowid.Repo.preload(corrected_invoice: :sales_invoice_items)
        |> Map.put(:seller_display_name, "Completely Different Company")

      assert_raise RuntimeError, ~r/Seller data cannot change/, fn ->
        InvoiceRenderer.render_fa3(kor1_with_changed_seller)
      end
    end

    test "does not raise when buyer non-ID data changes (name, address)" do
      original =
        [vat_rate: "23", buyer_name: "Old Buyer Name"]
        |> build_domestic_invoice()
        |> submit()

      kor1 = correct(original, buyer_name: "New Buyer Name", unit_price: "100.00")

      # Should render without raising — buyer name changes are allowed, only tax ID is guarded
      xml = render_xml(kor1)
      assert xml =~ "<RodzajFaktury>"
    end
  end

  # ---------------------------------------------------------------------------
  # VAT summary delta — uses reference invoice for before/after computation
  # ---------------------------------------------------------------------------

  describe "VAT summary delta uses reference invoice" do
    test "first correction: P_13_1/P_14_1 delta = KOR1 - original" do
      original = [unit_price: "100.00"] |> build_original() |> submit()
      kor1 = correct(original, unit_price: "150.00")

      xml = render_xml(kor1)
      doc = parse(xml)

      # Net delta at 23%: 150 - 100 = 50
      p13_1 = doc |> xpath(~x"//Fa/P_13_1/text()"s) |> Decimal.new()
      assert Decimal.eq?(p13_1, Decimal.new("50.00"))

      # VAT delta at 23%: 34.50 - 23.00 = 11.50
      p14_1 = doc |> xpath(~x"//Fa/P_14_1/text()"s) |> Decimal.new()
      assert Decimal.eq?(p14_1, Decimal.new("11.50"))
    end

    test "second correction: P_13_1/P_14_1 delta = KOR2 - KOR1" do
      {_original, _kor1, kor2, _kor3} = build_correction_chain()

      xml = render_xml(kor2)
      doc = parse(xml)

      # Net delta at 23%: 200 - 150 = 50
      p13_1 = doc |> xpath(~x"//Fa/P_13_1/text()"s) |> Decimal.new()
      assert Decimal.eq?(p13_1, Decimal.new("50.00"))

      # VAT delta at 23%: 46.00 - 34.50 = 11.50
      p14_1 = doc |> xpath(~x"//Fa/P_14_1/text()"s) |> Decimal.new()
      assert Decimal.eq?(p14_1, Decimal.new("11.50"))
    end
  end
end
