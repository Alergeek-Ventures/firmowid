defmodule Firmowid.CostInvoicesTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.CostInvoices
  alias Firmowid.CostInvoices.CostInvoice

  describe "delete_cost_invoice/1" do
    test "returns error for KSeF-imported invoice and does not delete it" do
      user = user_fixture()
      invoice = insert_ksef_cost_invoice!(user.organization_id)

      assert_raise RuntimeError, ~r/Cost invoice #{invoice.id} is imported from KSeF and cannot be deleted/, fn ->
        CostInvoices.delete_cost_invoice(invoice.id)
      end

      assert Repo.get(CostInvoice, invoice.id)
    end
  end

  describe "ksef_cost_invoice_trigger" do
    test "blocks deleting KSeF-imported invoices on DB level" do
      user = user_fixture()
      invoice = insert_ksef_cost_invoice!(user.organization_id)

      assert_raise Postgrex.Error, ~r/Cannot delete a KSeF-imported cost invoice/, fn ->
        Repo.delete!(invoice)
      end
    end
  end

  describe "cost invoice lists" do
    test "hides only corrections whose original invoice exists in list_cost_invoices/2" do
      user = user_fixture()

      visible_invoice = insert_cost_invoice!(user.organization_id, %{invoice_identifier: "VISIBLE-REGULAR"})

      original_invoice =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORIGINAL-INVOICE",
          ksef_number: "KSEF-ORIGINAL-123"
        })

      visible_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "VISIBLE-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: nil,
          total_amount: Decimal.new("10.00")
        })

      hidden_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "HIDDEN-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-ORIGINAL-123",
          total_amount: Decimal.new("10.00")
        })

      orphaned_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORPHANED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-MISSING-ORIGINAL-123",
          total_amount: Decimal.new("10.00")
        })

      invoices = CostInvoices.list_cost_invoices(~D[2026-02-01], ~D[2026-02-28])

      invoice_ids = Enum.map(invoices, & &1.id)

      assert visible_invoice.id in invoice_ids
      assert original_invoice.id in invoice_ids
      assert visible_correction.id in invoice_ids
      assert orphaned_correction.id in invoice_ids
      refute hidden_correction.id in invoice_ids
    end

    test "hides only corrections whose original invoice exists from list_unmatched_cost_invoices/3" do
      user = user_fixture()

      visible_invoice = insert_cost_invoice!(user.organization_id, %{invoice_identifier: "VISIBLE-UNMATCHED"})

      original_invoice =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORIGINAL-UNMATCHED-INVOICE",
          ksef_number: "KSEF-ORIGINAL-456"
        })

      visible_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "VISIBLE-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: nil,
          total_amount: Decimal.new("12.34")
        })

      hidden_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "HIDDEN-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-ORIGINAL-456",
          total_amount: Decimal.new("12.34")
        })

      orphaned_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORPHANED-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-MISSING-ORIGINAL-456",
          total_amount: Decimal.new("12.34")
        })

      invoices =
        CostInvoices.list_unmatched_cost_invoices(~D[2026-02-01], ~D[2026-02-28], user.organization_id)

      invoice_ids = Enum.map(invoices, & &1.id)

      assert visible_invoice.id in invoice_ids
      assert original_invoice.id in invoice_ids
      assert visible_correction.id in invoice_ids
      assert orphaned_correction.id in invoice_ids
      refute hidden_correction.id in invoice_ids
    end
  end

  defp insert_ksef_cost_invoice!(organization_id) do
    attrs = %{
      seller: "KSeF Supplier Sp. z o.o.",
      seller_display_name: "KSeF Supplier",
      seller_address: "ul. Przykładowa 1, 00-001 Warszawa",
      sale_date: ~D[2026-02-01],
      issue_date: ~D[2026-02-01],
      due_date: ~D[2026-02-14],
      total_amount: Decimal.new("-123.45"),
      currency: "PLN",
      description: "Import z KSeF",
      invoice_identifier: "FV/2026/02/001",
      skip_invoicing: false,
      organization_id: organization_id,
      ksef_number: "KSEF-2026-TEST-#{System.unique_integer([:positive])}",
      ksef_permanent_storage_date: ~N[2026-02-01 12:00:00],
      ksef_downloaded_at: DateTime.utc_now()
    }

    %CostInvoice{}
    |> CostInvoice.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_cost_invoice!(organization_id, attrs) do
    base_attrs = %{
      seller: "Supplier Sp. z o.o.",
      seller_display_name: "Supplier",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      sale_date: ~D[2026-02-01],
      issue_date: ~D[2026-02-01],
      due_date: ~D[2026-02-14],
      total_amount: Decimal.new("-123.45"),
      currency: "PLN",
      description: "Test invoice",
      invoice_identifier: "FV/2026/02/#{System.unique_integer([:positive])}",
      skip_invoicing: false,
      organization_id: organization_id
    }

    %CostInvoice{}
    |> CostInvoice.changeset(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end
end
