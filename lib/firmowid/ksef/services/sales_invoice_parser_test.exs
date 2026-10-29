defmodule Firmowid.Ksef.Services.SalesInvoiceParserTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.Ksef.KsefTestHelpers

  alias Firmowid.Ksef.Services.InvoiceRenderer
  alias Firmowid.Ksef.Services.SalesInvoiceParser

  setup do
    %{org_id: Firmowid.AccountsFixtures.user_fixture().member.organization_id}
  end

  # Invoices rendered by Firmowid stand in for any FA(3) issuer: parsing must give back what was rendered.
  test "reads back a company invoice with several VAT rates", %{org_id: org_id} do
    invoice = build_multi_rate_invoice(org_id: org_id)

    assert {:ok, attrs} = invoice |> render() |> SalesInvoiceParser.parse()

    assert Map.take(attrs, document_fields()) == Map.take(invoice, document_fields())
    assert attrs.ksef_invoice_kind == :vat
    assert attrs.buyer_type == :company
    assert attrs.buyer_full_name == invoice.buyer_full_name
    assert items(attrs) == items(invoice)
  end

  test "reads back EU VAT and reverse charge buyers", %{org_id: org_id} do
    for invoice <- [
          build_eu_vat_invoice(org_id: org_id),
          build_reverse_charge_invoice(org_id: org_id)
        ] do
      assert {:ok, attrs} = invoice |> render() |> SalesInvoiceParser.parse()

      assert Map.take(attrs, [:buyer_id, :buyer_country, :is_reverse_charge, :currency]) ==
               Map.take(invoice, [:buyer_id, :buyer_country, :is_reverse_charge, :currency])

      assert items(attrs) == items(invoice)
    end
  end

  test "reads a Polish buyer without a tax ID as an individual", %{org_id: org_id} do
    invoice = build_no_id_invoice(org_id: org_id)

    assert {:ok, attrs} = invoice |> render() |> SalesInvoiceParser.parse()

    assert %{
             buyer_type: :individual,
             buyer_id: nil,
             buyer_given_name: "Jan",
             buyer_surname: "Kowalski"
           } = attrs
  end

  test "keeps the corrected state of a correction and its original's KSeF number", %{
    org_id: org_id
  } do
    original =
      simulate_ksef_submission(build_domestic_invoice(org_id: org_id), with_ksef_number: true)

    correction = build_correction_invoice(original)

    assert {:ok, attrs} = correction |> render() |> SalesInvoiceParser.parse()

    assert attrs.ksef_invoice_kind == :kor
    assert attrs.corrected_invoice_ksef_number == original.ksef_number
    assert items(attrs) == items(correction)
  end

  test "reads back GTU, related parties and receipt invoice markers", %{org_id: org_id} do
    invoice = build_domestic_invoice(org_id: org_id)
    [item] = invoice.sales_invoice_items
    Ash.Seed.update!(item, %{gtu: "GTU_12"})

    invoice =
      invoice
      |> Ash.Seed.update!(%{related_parties: true, receipt_invoice: true})
      |> Ash.load!([sales_invoice_items: [:net_value, :vat_value, :gross_value]],
        actor: %Firmowid.SystemActor{org_id: org_id, role: :sales_invoice_processor},
        tenant: org_id
      )

    assert {:ok, attrs} = invoice |> render() |> SalesInvoiceParser.parse()

    assert %{related_parties: true, receipt_invoice: true} = attrs
    assert [%{gtu: "GTU_12"}] = attrs.sales_invoice_items
  end

  test "rejects invoice kinds a sales invoice cannot represent", %{org_id: org_id} do
    xml =
      [org_id: org_id]
      |> build_domestic_invoice()
      |> render()
      |> String.replace(
        ~r/<RodzajFaktury>\s*VAT\s*<\/RodzajFaktury>/,
        "<RodzajFaktury>ZAL</RodzajFaktury>"
      )

    assert {:error, {:unsupported, "invoice kind ZAL"}} = SalesInvoiceParser.parse(xml)
  end

  defp render(invoice), do: invoice |> InvoiceRenderer.render_fa3() |> IO.iodata_to_binary()

  defp document_fields do
    [
      :invoice_number,
      :issue_date,
      :sale_date,
      :due_date,
      :currency,
      :payment_method,
      :seller_nip,
      :seller_display_name,
      :seller_address,
      :seller_account_number,
      :buyer_id,
      :buyer_address,
      :buyer_country
    ]
  end

  defp items(%{sales_invoice_items: items}) do
    Enum.map(items, fn item ->
      {item.name, item.unit, Decimal.normalize(item.quantity), Decimal.normalize(item.unit_price), item.vat_rate}
    end)
  end
end
