defmodule Firmowid.Ash.Invoicing.Services.MonthDownloadEntriesTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Invoicing.Services.MonthDownloadEntries
  alias Firmowid.Ash.Scope

  test "build/3 selects invoices from selected month using :any date field" do
    admin = admin_fixture()
    org_id = admin.organization_id
    scope = %Scope{actor: admin, tenant: org_id}

    # Included by sale_date in March, despite issue_date in April
    blob_pdf = seed_blob!(org_id, "sale-month.pdf", "service-sale-month-pdf")

    _included_cost_pdf =
      Ash.Seed.seed!(CostInvoice, %{
        seller: "Sale Month PDF Seller",
        seller_display_name: "Sale Month PDF Seller",
        invoice_identifier: "CI-SALE-MONTH-PDF",
        description: "Included by sale_date",
        sale_date: ~D[2026-03-28],
        issue_date: ~D[2026-04-01],
        due_date: ~D[2026-04-10],
        amount: Money.new!("PLN", Decimal.new("-120.00")),
        organization_id: org_id,
        blob_id: blob_pdf.id
      })

    blob_xml = seed_blob!(org_id, "ksef-march.xml", "service-ksef-march-xml")

    _excluded_cost_xml =
      Ash.Seed.seed!(CostInvoice, %{
        seller: "KSeF March Seller",
        seller_display_name: "KSeF March Seller",
        invoice_identifier: "CI-KSEF-MARCH",
        description: "Excluded when include_ksef=false",
        sale_date: ~D[2026-03-10],
        issue_date: ~D[2026-03-10],
        due_date: ~D[2026-03-20],
        amount: Money.new!("PLN", Decimal.new("-80.00")),
        organization_id: org_id,
        blob_id: blob_xml.id
      })

    blob_outside = seed_blob!(org_id, "outside-month.pdf", "service-outside-month-pdf")

    _outside_cost =
      Ash.Seed.seed!(CostInvoice, %{
        seller: "Outside Month Seller",
        seller_display_name: "Outside Month Seller",
        invoice_identifier: "CI-OUTSIDE",
        description: "Outside selected month",
        sale_date: ~D[2026-04-12],
        issue_date: ~D[2026-04-12],
        due_date: ~D[2026-04-20],
        amount: Money.new!("PLN", Decimal.new("-60.00")),
        organization_id: org_id,
        blob_id: blob_outside.id
      })

    _included_sales =
      seed_sales_invoice!(
        org_id,
        ~D[2026-04-01],
        ~D[2026-03-27],
        "03/03/2026",
        "Buyer Sale Month"
      )

    _outside_sales =
      seed_sales_invoice!(
        org_id,
        ~D[2026-04-11],
        ~D[2026-04-11],
        "01/04/2026",
        "Buyer Outside"
      )

    entries =
      MonthDownloadEntries.build(
        ~D[2026-03-01],
        %{include_digital: true, include_ksef: false, include_photos: false, include_sales: true},
        scope
      )

    assert Enum.any?(entries, &String.starts_with?(&1.path, "kosztowe/"))
    assert Enum.any?(entries, &String.starts_with?(&1.path, "sprzedazowe/"))

    refute Enum.any?(entries, fn entry ->
             path = entry.path
             String.contains?(path, "outside") or String.ends_with?(path, ".xml")
           end)
  end

  test "build/3 respects file-type filters for cost invoices" do
    admin = admin_fixture()
    org_id = admin.organization_id
    scope = %Scope{actor: admin, tenant: org_id}

    blob_pdf = seed_blob!(org_id, "type-filter.pdf", "service-type-filter-pdf")
    _pdf = seed_cost_invoice!(org_id, blob_pdf.id, ~D[2026-03-05], "Type PDF")

    blob_xml = seed_blob!(org_id, "type-filter.xml", "service-type-filter-xml")
    _xml = seed_cost_invoice!(org_id, blob_xml.id, ~D[2026-03-06], "Type XML")

    blob_jpg = seed_blob!(org_id, "type-filter.jpg", "service-type-filter-jpg")
    _jpg = seed_cost_invoice!(org_id, blob_jpg.id, ~D[2026-03-07], "Type JPG")

    entries =
      MonthDownloadEntries.build(
        ~D[2026-03-01],
        %{include_digital: false, include_ksef: true, include_photos: true, include_sales: false},
        scope
      )

    refute Enum.any?(entries, &String.ends_with?(&1.path, ".pdf"))
    assert Enum.any?(entries, &String.ends_with?(&1.path, ".xml"))
    assert Enum.any?(entries, &String.ends_with?(&1.path, ".jpg"))
    refute Enum.any?(entries, &String.starts_with?(&1.path, "sprzedazowe/"))
  end

  defp seed_blob!(organization_id, filename, checksum) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/path/#{filename}",
      blob_checksum: checksum,
      original_filename: filename,
      organization_id: organization_id
    })
  end

  defp seed_cost_invoice!(organization_id, blob_id, issue_date, seller_display_name) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: seller_display_name,
      seller_display_name: seller_display_name,
      invoice_identifier: "CI-TYPE-#{System.unique_integer([:positive])}",
      description: "Type filter fixture",
      sale_date: issue_date,
      issue_date: issue_date,
      due_date: issue_date,
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      skip_invoicing: false,
      organization_id: organization_id,
      blob_id: blob_id
    })
  end

  defp seed_sales_invoice!(organization_id, issue_date, sale_date, invoice_number, buyer_name) do
    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: invoice_number,
        buyer_full_name: buyer_name,
        buyer_display_name: buyer_name,
        seller_display_name: "Our Company",
        sale_date: sale_date,
        issue_date: issue_date,
        due_date: issue_date,
        payment_method: :transfer,
        currency: "PLN",
        buyer_type: :company,
        organization_id: organization_id
      })

    Ash.Seed.seed!(SalesInvoiceItem, %{
      sales_invoice_id: invoice.id,
      name: "Service",
      index: 0,
      quantity: 1,
      unit: "pcs",
      unit_price: Decimal.new("100.00"),
      vat_rate: "23",
      organization_id: organization_id
    })

    invoice
  end
end
