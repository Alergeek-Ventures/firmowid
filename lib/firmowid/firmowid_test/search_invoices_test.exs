defmodule Firmowid.InvoicesSearchTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Blobs.Blob
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.CostInvoices.CostInvoicesTransactions
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  describe "search_invoices/1" do
    test "returns matching invoices using BM25 search" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      sales_invoice1 =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-ACME-123",
          buyer_full_name: "Acme Corp",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-01-01],
          issue_date: ~D[2024-01-01],
          due_date: ~D[2024-01-31],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id
        })

      blob1 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/acme_invoice_1.pdf",
          blob_checksum: "acme_checksum_1",
          original_filename: "acme_invoice_1.pdf",
          organization_id: organization_id
        })

      cost_invoice1 =
        Repo.insert!(%CostInvoice{
          seller: "Acme Solutions",
          seller_display_name: "Acme Solutions",
          invoice_identifier: "CI-ACME-456",
          description: "Software license for Acme",
          sale_date: ~D[2024-01-05],
          issue_date: ~D[2024-01-05],
          due_date: ~D[2024-02-05],
          total_amount: Decimal.new("-100.00"),
          currency: "USD",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob1.id
        })

      _sales_invoice2 =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-OTHER-789",
          buyer_full_name: "Another Company",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-02-01],
          issue_date: ~D[2024-02-01],
          due_date: ~D[2024-02-28],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id
        })

      blob2 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/other_invoice_2.pdf",
          blob_checksum: "other_checksum_2",
          original_filename: "other_invoice_2.pdf",
          organization_id: organization_id
        })

      _cost_invoice2 =
        Repo.insert!(%CostInvoice{
          seller: "Other Supplier",
          seller_display_name: "Other Supplier",
          invoice_identifier: "CI-OTHER-987",
          description: "Office supplies",
          sale_date: ~D[2024-02-10],
          issue_date: ~D[2024-02-10],
          due_date: ~D[2024-03-10],
          total_amount: Decimal.new("-50.00"),
          currency: "USD",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob2.id
        })

      # Run the search
      results = Invoicing.search_invoices(%{query: "Acme", currency: "USD"})

      assert length(results) == 2

      found_sales_invoice = Enum.find(results, &(&1.__struct__ == SalesInvoice))
      found_cost_invoice = Enum.find(results, &(&1.__struct__ == CostInvoice))

      assert found_sales_invoice.id == sales_invoice1.id
      assert found_sales_invoice.buyer_full_name == "Acme Corp"

      assert found_cost_invoice.id == cost_invoice1.id
      assert found_cost_invoice.seller == "Acme Solutions"
    end

    test "returns empty list when no matches found" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      _ =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-SOME-111",
          buyer_full_name: "Some Company",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-03-01],
          issue_date: ~D[2024-03-01],
          due_date: ~D[2024-03-31],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id
        })

      blob3 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/another_vendor_invoice_3.pdf",
          blob_checksum: "another_vendor_checksum_3",
          original_filename: "another_vendor_invoice_3.pdf",
          organization_id: organization_id
        })

      _ =
        Repo.insert!(%CostInvoice{
          seller: "Another Vendor",
          seller_display_name: "Another Vendor",
          invoice_identifier: "CI-ANOTHER-222",
          description: "Consulting services",
          sale_date: ~D[2024-03-05],
          issue_date: ~D[2024-03-05],
          due_date: ~D[2024-04-05],
          total_amount: Decimal.new("-200.00"),
          currency: "USD",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob3.id
        })

      results = Invoicing.search_invoices(%{query: "NonExistent"})
      assert results == []
    end

    test "does not find invoices across organizations" do
      # Create user and invoices in org1
      user1 = user_fixture()
      org1_id = user1.organization_id

      si1 =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-ORG1-UNIQUE",
          buyer_full_name: "Org1 Buyer",
          seller_display_name: "Org1 Seller",
          sale_date: ~D[2024-01-01],
          issue_date: ~D[2024-01-01],
          due_date: ~D[2024-01-31],
          payment_method: :transfer,
          currency: "PLN",
          buyer_type: :company,
          organization_id: org1_id
        })

      blob4 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/org1_invoice_4.pdf",
          blob_checksum: "org1_checksum_4",
          original_filename: "org1_invoice_4.pdf",
          organization_id: org1_id
        })

      ci1 =
        Repo.insert!(%CostInvoice{
          seller: "Org1 Vendor",
          seller_display_name: "Org1 Vendor",
          invoice_identifier: "CI-ORG1-UNIQUE",
          description: "Org1 unique item",
          sale_date: ~D[2024-01-05],
          issue_date: ~D[2024-01-05],
          due_date: ~D[2024-02-05],
          total_amount: Decimal.new("-100.00"),
          currency: "PLN",
          skip_invoicing: false,
          organization_id: org1_id,
          blob_id: blob4.id
        })

      # Create user and invoices in org2
      user2 = user_fixture()
      org2_id = user2.organization_id

      si2 =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-ORG2-UNIQUE",
          buyer_full_name: "Org2 Buyer",
          seller_display_name: "Org2 Seller",
          sale_date: ~D[2024-02-01],
          issue_date: ~D[2024-02-01],
          due_date: ~D[2024-02-28],
          payment_method: :transfer,
          currency: "PLN",
          buyer_type: :company,
          organization_id: org2_id
        })

      blob5 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/org2_invoice_5.pdf",
          blob_checksum: "org2_checksum_5",
          original_filename: "org2_invoice_5.pdf",
          organization_id: org2_id
        })

      ci2 =
        Repo.insert!(%CostInvoice{
          seller: "Org2 Vendor",
          seller_display_name: "Org2 Vendor",
          invoice_identifier: "CI-ORG2-UNIQUE",
          description: "Org2 unique item",
          sale_date: ~D[2024-02-05],
          issue_date: ~D[2024-02-05],
          due_date: ~D[2024-03-05],
          total_amount: Decimal.new("-200.00"),
          currency: "PLN",
          skip_invoicing: false,
          organization_id: org2_id,
          blob_id: blob5.id
        })

      # Set org context to org1, search for org2's invoices
      Repo.put_org_id(org1_id)
      results = Invoicing.search_invoices(%{query: "Org2"})
      assert results == []

      # Set org context to org2, search for org1's invoices
      Repo.put_org_id(org2_id)
      results = Invoicing.search_invoices(%{query: "Org1"})
      assert results == []

      # Set org context to org1, search for org1's invoices
      Repo.put_org_id(org1_id)
      results = Invoicing.search_invoices(%{query: "Org1"})
      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == si1.id))
      assert Enum.any?(results, &(&1.id == ci1.id))

      # Set org context to org2, search for org2's invoices
      Repo.put_org_id(org2_id)
      results = Invoicing.search_invoices(%{query: "Org2"})
      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == si2.id))
      assert Enum.any?(results, &(&1.id == ci2.id))
    end

    test "filters by only_unmatched" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      # Unmatched invoices
      unmatched_sales_invoice =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-UNMATCHED-1",
          buyer_full_name: "Unmatched Sales",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-04-01],
          issue_date: ~D[2024-04-01],
          due_date: ~D[2024-04-30],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          skip_invoicing: false,
          organization_id: organization_id
        })

      unmatched_sales_invoice_skipped =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-UNMATCHED-2",
          buyer_full_name: "Unmatched Sales",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-04-01],
          issue_date: ~D[2024-04-01],
          due_date: ~D[2024-04-30],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          skip_invoicing: true,
          organization_id: organization_id
        })

      blob6 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/unmatched_cost_invoice_6.pdf",
          blob_checksum: "unmatched_cost_checksum_6",
          original_filename: "unmatched_cost_invoice_6.pdf",
          organization_id: organization_id
        })

      unmatched_cost_invoice =
        Repo.insert!(%CostInvoice{
          seller: "Unmatched Cost",
          seller_display_name: "Unmatched Cost",
          invoice_identifier: "CI-UNMATCHED-1",
          description: "Unmatched item",
          sale_date: ~D[2024-04-05],
          issue_date: ~D[2024-04-05],
          due_date: ~D[2024-05-05],
          total_amount: Decimal.new("-10.00"),
          currency: "USD",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob6.id
        })

      # Matched invoices
      matched_sales_invoice =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-MATCHED-1",
          buyer_full_name: "Matched Sales",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-04-10],
          issue_date: ~D[2024-04-10],
          due_date: ~D[2024-05-10],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id
        })

      blob7 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/matched_cost_invoice_7.pdf",
          blob_checksum: "matched_cost_checksum_7",
          original_filename: "matched_cost_invoice_7.pdf",
          organization_id: organization_id
        })

      matched_cost_invoice =
        Repo.insert!(%CostInvoice{
          seller: "Matched Cost",
          seller_display_name: "Matched Cost",
          invoice_identifier: "CI-MATCHED-1",
          description: "Matched item",
          sale_date: ~D[2024-04-15],
          issue_date: ~D[2024-04-15],
          due_date: ~D[2024-05-15],
          total_amount: Decimal.new("-20.00"),
          currency: "USD",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob7.id
        })

      # Create transactions and link them to the "matched" invoices
      transaction_for_sales =
        Repo.insert!(%Transaction{
          transaction_id: "TX-SALES-1",
          creditor_name: "Matched Sales Transaction",
          creditor_account: "ACC123",
          debtor_name: "Our Company",
          debtor_account: "ACC456",
          transaction_amount: Decimal.new("100.00"),
          transaction_currency: "USD",
          booking_date: ~D[2024-04-10],
          value_date: ~D[2024-04-10],
          remittance_information_unstructured: "Payment for SI-MATCHED-1",
          bank_account_id: nil,
          organization_id: organization_id
        })

      transaction_for_cost =
        Repo.insert!(%Transaction{
          transaction_id: "TX-COST-1",
          creditor_name: "Our Company",
          creditor_account: "ACC456",
          debtor_name: "Matched Cost Transaction",
          debtor_account: "ACC789",
          transaction_amount: Decimal.new("20.00"),
          transaction_currency: "USD",
          booking_date: ~D[2024-04-15],
          value_date: ~D[2024-04-15],
          remittance_information_unstructured: "Payment for CI-MATCHED-1",
          bank_account_id: nil,
          organization_id: organization_id
        })

      Firmowid.SalesInvoices.create_sales_invoices_transactions_connection(
        matched_sales_invoice.id,
        transaction_for_sales.id,
        organization_id
      )

      Repo.insert!(%CostInvoicesTransactions{
        cost_invoice_id: matched_cost_invoice.id,
        transaction_id: transaction_for_cost.id,
        organization_id: organization_id
      })

      results = Invoicing.search_invoices(%{only_unmatched: true})

      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == unmatched_sales_invoice.id))
      assert Enum.any?(results, &(&1.id == unmatched_cost_invoice.id))
      refute Enum.any?(results, &(&1.id == matched_sales_invoice.id))
      refute Enum.any?(results, &(&1.id == matched_cost_invoice.id))
      refute Enum.any?(results, &(&1.id == unmatched_sales_invoice_skipped.id))
    end

    test "filters sales invoices by buyer_type" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      sales_invoice_company =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-COMPANY-1",
          buyer_full_name: "Company Buyer Inc.",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-05-01],
          issue_date: ~D[2024-05-01],
          due_date: ~D[2024-05-31],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id
        })

      sales_invoice_individual =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-INDIVIDUAL-1",
          buyer_given_name: "John",
          buyer_surname: "Doe",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-05-05],
          issue_date: ~D[2024-05-05],
          due_date: ~D[2024-06-05],
          payment_method: :cash,
          currency: "USD",
          buyer_type: :individual,
          organization_id: organization_id
        })

      blob8 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/some_vendor_invoice_8.pdf",
          blob_checksum: "some_vendor_checksum_8",
          original_filename: "some_vendor_invoice_8.pdf",
          organization_id: organization_id
        })

      _cost_invoice =
        Repo.insert!(%CostInvoice{
          seller: "Some Vendor",
          seller_display_name: "Some Vendor",
          invoice_identifier: "CI-VENDOR-1",
          description: "Some cost",
          sale_date: ~D[2024-05-10],
          issue_date: ~D[2024-05-10],
          due_date: ~D[2024-06-10],
          total_amount: Decimal.new("-50.00"),
          currency: "USD",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob8.id
        })

      # Test for :company buyer_type
      results_company = Invoicing.search_invoices(%{buyer_type: :company})
      assert length(results_company) == 1
      assert Enum.any?(results_company, &(&1.id == sales_invoice_company.id))
      refute Enum.any?(results_company, &(&1.id == sales_invoice_individual.id))

      # Test for :individual buyer_type
      results_individual = Invoicing.search_invoices(%{buyer_type: :individual})
      assert length(results_individual) == 1
      assert Enum.any?(results_individual, &(&1.id == sales_invoice_individual.id))
      refute Enum.any?(results_individual, &(&1.id == sales_invoice_company.id))
    end
  end

  describe "search_invoices/1 with amount and date filters" do
    setup do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      si1 =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-ALPHA-1",
          buyer_full_name: "Alpha Corp",
          seller_display_name: "Our Company",
          # total_amount: Decimal.new("123.00"),
          issue_date: ~D[2024-01-01],
          sale_date: ~D[2024-01-02],
          due_date: ~D[2024-01-31],
          payment_method: :transfer,
          currency: "PLN",
          buyer_type: :company,
          organization_id: organization_id
        })

      si2 =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-BETA-2",
          buyer_full_name: "Beta Corp",
          seller_display_name: "Our Company",
          # total_amount: Decimal.new("246.00"),
          issue_date: ~D[2024-02-01],
          sale_date: ~D[2024-02-02],
          due_date: ~D[2024-02-28],
          payment_method: :transfer,
          currency: "PLN",
          buyer_type: :company,
          organization_id: organization_id
        })

      si3 =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-GAMMA-3",
          buyer_full_name: "Gamma Corp",
          seller_display_name: "Our Company",
          # total_amount: Decimal.new("369.00"),
          issue_date: ~D[2024-03-01],
          sale_date: ~D[2024-03-02],
          due_date: ~D[2024-03-31],
          payment_method: :transfer,
          currency: "PLN",
          buyer_type: :company,
          organization_id: organization_id
        })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: si1.id,
        name: "Item 1",
        index: 0,
        quantity: 1,
        unit: "pcs",
        unit_price: Decimal.new("100.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: si2.id,
        name: "Item 2",
        index: 0,
        quantity: 1,
        unit: "pcs",
        unit_price: Decimal.new("100.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: si2.id,
        name: "Item 3",
        index: 1,
        quantity: 1,
        unit: "pcs",
        unit_price: Decimal.new("100.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: si3.id,
        name: "Item 4",
        index: 0,
        quantity: 1,
        unit: "pcs",
        unit_price: Decimal.new("100.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: si3.id,
        name: "Item 5",
        index: 1,
        quantity: 1,
        unit: "pcs",
        unit_price: Decimal.new("200.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      si1 = Repo.preload(si1, :sales_invoice_items)
      si2 = Repo.preload(si2, :sales_invoice_items)
      si3 = Repo.preload(si3, :sales_invoice_items)
      %{si1: si1, si2: si2, si3: si3}
    end

    test "filters by amount_gt and amount_lt", %{si1: _si1, si2: si2, si3: _si3} do
      results =
        Invoicing.search_invoices(%{
          amount_gt: Decimal.new("210.00"),
          amount_lt: Decimal.new("250.00")
        })

      assert Enum.map(results, & &1.id) == [si2.id]
    end

    test "filters by date_from and date_to", %{
      si1: si1,
      si2: si2,
      si3: si3
    } do
      # Should match si2 and si3 (issue_date in range)
      results =
        Invoicing.search_invoices(%{date_from: ~D[2024-02-01], date_to: ~D[2024-03-01]})

      ids = Enum.map(results, & &1.id)
      assert si2.id in ids
      assert si3.id in ids
      refute si1.id in ids
    end

    test "matches if issue_date is in range", %{si1: si1, si2: _si2, si3: _si3} do
      # search_invoices filters sales invoices by issue_date
      results =
        Invoicing.search_invoices(%{date_from: ~D[2024-01-01], date_to: ~D[2024-01-01]})

      assert Enum.map(results, & &1.id) == [si1.id]
    end

    test "filters by include_sales and include_cost" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      sales_invoice =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-FILTER-SALES",
          buyer_full_name: "Sales Filter Co",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-06-01],
          issue_date: ~D[2024-06-01],
          due_date: ~D[2024-06-30],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id
        })

      blob9 =
        Repo.insert!(%Blob{
          blob_path: "/test/path/cost_filter_invoice_9.pdf",
          blob_checksum: "cost_filter_checksum_9",
          original_filename: "cost_filter_invoice_9.pdf",
          organization_id: organization_id
        })

      cost_invoice =
        Repo.insert!(%CostInvoice{
          seller: "Cost Filter Inc",
          seller_display_name: "Cost Filter Inc",
          invoice_identifier: "CI-FILTER-COST",
          description: "Cost filter item",
          sale_date: ~D[2024-06-05],
          issue_date: ~D[2024-06-05],
          due_date: ~D[2024-07-05],
          total_amount: Decimal.new("-75.00"),
          currency: "USD",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob9.id
        })

      # Test include_sales: true, include_cost: false
      results_only_sales =
        Invoicing.search_invoices(%{query: "Filter", include_sales: true, include_cost: false})

      assert length(results_only_sales) == 1
      assert Enum.any?(results_only_sales, &(&1.id == sales_invoice.id))
      refute Enum.any?(results_only_sales, &(&1.__struct__ == CostInvoice))

      # Test include_sales: false, include_cost: true
      results_only_cost =
        Invoicing.search_invoices(%{query: "Filter", include_sales: false, include_cost: true})

      assert length(results_only_cost) == 1
      assert Enum.any?(results_only_cost, &(&1.id == cost_invoice.id))
      refute Enum.any?(results_only_cost, &(&1.__struct__ == SalesInvoice))

      # Test include_sales: true, include_cost: true (or default behavior)
      results_both =
        Invoicing.search_invoices(%{query: "Filter", include_sales: true, include_cost: true})

      assert length(results_both) == 2
      assert Enum.any?(results_both, &(&1.id == sales_invoice.id))
      assert Enum.any?(results_both, &(&1.id == cost_invoice.id))

      # Test include_sales: false, include_cost: false
      results_none =
        Invoicing.search_invoices(%{query: "Filter", include_sales: false, include_cost: false})

      assert results_none == []
    end

    test "searches in sales invoice item_names" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      sales_invoice_with_items =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-ITEM-SEARCH",
          buyer_full_name: "Item Search Buyer",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-07-01],
          issue_date: ~D[2024-07-01],
          due_date: ~D[2024-07-31],
          payment_method: :transfer,
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id,
          item_names: "Consulting Services for Project X"
        })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: sales_invoice_with_items.id,
        name: "Consulting Services for Project X",
        index: 0,
        quantity: 1,
        unit: "hour",
        unit_price: Decimal.new("500.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: sales_invoice_with_items.id,
        name: "Software License Fee",
        index: 1,
        quantity: 1,
        unit: "license",
        unit_price: Decimal.new("1000.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      # Search for a term in item_names
      results = Invoicing.search_invoices(%{query: "Project X"})
      assert length(results) == 1
      assert Enum.any?(results, &(&1.id == sales_invoice_with_items.id))

      results_software = Invoicing.search_invoices(%{query: "Software License"})
      assert length(results_software) == 1
      assert Enum.any?(results_software, &(&1.id == sales_invoice_with_items.id))

      results_no_match = Invoicing.search_invoices(%{query: "Hardware"})
      assert results_no_match == []
    end

    test "uses all common search parameters simultaneously" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      # Matching Sales Invoice
      sales_invoice_combined_match =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-COMBINED-MATCH",
          buyer_full_name: "Combined Search Buyer",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-08-10],
          issue_date: ~D[2024-08-10],
          due_date: ~D[2024-08-31],
          payment_method: :transfer,
          currency: "EUR",
          buyer_type: :company,
          organization_id: organization_id,
          item_names: "Combined Search Item 1 Combined Search Item 2"
        })

      Repo.insert!(%SalesInvoiceItem{
        sales_invoice_id: sales_invoice_combined_match.id,
        name: "Combined Search Item 1",
        index: 0,
        quantity: 1,
        unit: "hour",
        unit_price: Decimal.new("100.00"),
        vat_rate: "23",
        organization_id: organization_id
      })

      sales_invoice_combined_match =
        Repo.preload(sales_invoice_combined_match, [:sales_invoice_items, :transactions])

      # Matching Cost Invoice
      blob_combined_match =
        Repo.insert!(%Blob{
          blob_path: "/test/path/combined_cost_invoice.pdf",
          blob_checksum: "combined_cost_checksum",
          original_filename: "combined_cost_invoice.pdf",
          organization_id: organization_id
        })

      cost_invoice_combined_match =
        Repo.insert!(%CostInvoice{
          seller: "Combined Search Vendor",
          seller_display_name: "Combined Search Vendor",
          invoice_identifier: "CI-COMBINED-MATCH",
          description: "Combined Search Service",
          sale_date: ~D[2024-08-15],
          issue_date: ~D[2024-08-15],
          due_date: ~D[2024-08-15],
          total_amount: Decimal.new("-200.00"),
          currency: "EUR",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob_combined_match.id
        })

      # Non-matching Sales Invoice (different currency)
      _sales_invoice_diff_currency =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-DIFF-CURRENCY",
          buyer_full_name: "Combined Search Buyer USD",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-08-10],
          issue_date: ~D[2024-08-10],
          due_date: ~D[2024-08-31],
          payment_method: :transfer,
          # Different currency
          currency: "USD",
          buyer_type: :company,
          organization_id: organization_id
        })

      # Non-matching Cost Invoice (outside date range)
      blob_diff_date =
        Repo.insert!(%Blob{
          blob_path: "/test/path/diff_date_cost_invoice.pdf",
          blob_checksum: "diff_date_checksum",
          original_filename: "diff_date_cost_invoice.pdf",
          organization_id: organization_id
        })

      _cost_invoice_diff_date =
        Repo.insert!(%CostInvoice{
          seller: "Combined Search Vendor Sept",
          seller_display_name: "Combined Search Vendor Sept",
          invoice_identifier: "CI-DIFF-DATE",
          description: "Combined Search Service Sept",
          # Outside date range
          sale_date: ~D[2024-09-01],
          issue_date: ~D[2024-09-01],
          due_date: ~D[2024-10-01],
          total_amount: Decimal.new("-200.00"),
          currency: "EUR",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob_diff_date.id
        })

      # Non-matching Sales Invoice (already matched)
      sales_invoice_matched =
        Repo.insert!(%SalesInvoice{
          invoice_number: "SI-ALREADY-MATCHED",
          buyer_full_name: "Combined Search Buyer Matched",
          seller_display_name: "Our Company",
          sale_date: ~D[2024-08-20],
          issue_date: ~D[2024-08-20],
          due_date: ~D[2024-09-20],
          payment_method: :transfer,
          currency: "EUR",
          buyer_type: :company,
          organization_id: organization_id
        })

      transaction_for_matched_sales =
        Repo.insert!(%Transaction{
          transaction_id: "TX-MATCHED-SALES",
          creditor_name: "Matched Sales Transaction",
          creditor_account: "ACC123",
          debtor_name: "Our Company",
          debtor_account: "ACC456",
          transaction_amount: Decimal.new("150.00"),
          transaction_currency: "EUR",
          booking_date: ~D[2024-08-20],
          value_date: ~D[2024-08-20],
          remittance_information_unstructured: "Payment for SI-ALREADY-MATCHED",
          bank_account_id: nil,
          organization_id: organization_id
        })

      Firmowid.SalesInvoices.create_sales_invoices_transactions_connection(
        sales_invoice_matched.id,
        transaction_for_matched_sales.id,
        organization_id
      )

      # Non-matching Cost Invoice (amount out of range)
      blob_low_amount =
        Repo.insert!(%Blob{
          blob_path: "/test/path/low_amount_cost_invoice.pdf",
          blob_checksum: "low_amount_checksum",
          original_filename: "low_amount_cost_invoice.pdf",
          organization_id: organization_id
        })

      _cost_invoice_low_amount =
        Repo.insert!(%CostInvoice{
          seller: "Combined Search Vendor Low Amount",
          seller_display_name: "Combined Search Vendor Low Amount",
          invoice_identifier: "CI-LOW-AMOUNT",
          description: "Combined Search Service Low Amount",
          sale_date: ~D[2024-08-25],
          issue_date: ~D[2024-08-25],
          due_date: ~D[2024-09-25],
          # Too high
          total_amount: Decimal.new("-300.00"),
          currency: "EUR",
          skip_invoicing: false,
          organization_id: organization_id,
          blob_id: blob_low_amount.id
        })

      # Perform the search with all common parameters
      results =
        Invoicing.search_invoices(%{
          query: "Combined Search",
          currency: "EUR",
          only_unmatched: true,
          amount_gt: Decimal.new("-250.00"),
          amount_lt: Decimal.new("300.00"),
          date_from: ~D[2024-08-01],
          date_to: ~D[2024-08-31]
        })

      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == sales_invoice_combined_match.id))
      assert Enum.any?(results, &(&1.id == cost_invoice_combined_match.id))

      refute Enum.any?(results, &(&1.id == _sales_invoice_diff_currency.id))
      refute Enum.any?(results, &(&1.id == _cost_invoice_diff_date.id))
      refute Enum.any?(results, &(&1.id == sales_invoice_matched.id))
      refute Enum.any?(results, &(&1.id == _cost_invoice_low_amount.id))
    end
  end
end
