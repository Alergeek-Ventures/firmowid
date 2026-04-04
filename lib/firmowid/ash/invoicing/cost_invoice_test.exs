defmodule Firmowid.Ash.Invoicing.CostInvoiceTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  @bridge_opts [authorize?: false, actor: %{}]

  describe "delete_cost_invoice/1" do
    test "returns error for KSeF-imported invoice and does not delete it" do
      user = user_fixture()
      invoice = insert_ksef_cost_invoice!(user.organization_id)

      assert_raise RuntimeError,
                   ~r/Cost invoice #{invoice.id} is imported from KSeF and cannot be deleted/,
                   fn ->
                     Invoicing.delete_cost_invoice(invoice.id)
                   end

      opts = [tenant: user.organization_id] ++ @bridge_opts
      assert {:ok, _} = Invoicing.get_cost_invoice(invoice.id, opts)
    end
  end

  describe "cost invoice lists" do
    test "hides only corrections whose original invoice exists in list_for_month" do
      user = user_fixture()
      opts = [tenant: user.organization_id] ++ @bridge_opts

      visible_invoice =
        insert_cost_invoice!(user.organization_id, %{invoice_identifier: "VISIBLE-REGULAR"})

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

      _hidden_correction =
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

      invoices =
        Invoicing.list_cost_invoices!(
          %{date_from: ~D[2026-02-01], date_to: ~D[2026-02-28], date_field: :issue_date},
          opts
        )

      invoice_ids = Enum.map(invoices, & &1.id)

      assert visible_invoice.id in invoice_ids
      assert original_invoice.id in invoice_ids
      assert visible_correction.id in invoice_ids
      assert orphaned_correction.id in invoice_ids
      refute Enum.any?(invoices, &(&1.invoice_identifier == "HIDDEN-CORRECTION"))
    end

    test "hides only corrections whose original invoice exists from list_unmatched" do
      user = user_fixture()
      opts = [tenant: user.organization_id] ++ @bridge_opts

      visible_invoice =
        insert_cost_invoice!(user.organization_id, %{invoice_identifier: "VISIBLE-UNMATCHED"})

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

      _hidden_correction =
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
        Invoicing.list_cost_invoices!(
          %{
            date_from: ~D[2026-02-01],
            date_to: ~D[2026-02-28],
            date_field: :due_date,
            reconciliation: :pending
          },
          opts
        )

      invoice_ids = Enum.map(invoices, & &1.id)

      assert visible_invoice.id in invoice_ids
      assert original_invoice.id in invoice_ids
      assert visible_correction.id in invoice_ids
      assert orphaned_correction.id in invoice_ids
      refute Enum.any?(invoices, &(&1.invoice_identifier == "HIDDEN-UNMATCHED-CORRECTION"))
    end
  end

  defp insert_ksef_cost_invoice!(organization_id) do
    Ash.Seed.seed!(CostInvoice, %{
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
    })
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

    Ash.Seed.seed!(CostInvoice, Map.merge(base_attrs, attrs))
  end
end
