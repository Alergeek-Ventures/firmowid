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

  describe "toggle_skip_invoicing/1" do
    test "allows toggling skip flag for KSeF-imported invoice" do
      user = user_fixture()
      invoice = insert_ksef_cost_invoice!(user.organization_id)

      updated_invoice = CostInvoices.toggle_skip_invoicing(invoice.id)

      assert updated_invoice.skip_invoicing
      assert Repo.get!(CostInvoice, invoice.id).skip_invoicing
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

    test "blocks updates to KSeF XML data on DB level" do
      user = user_fixture()
      invoice = insert_ksef_cost_invoice!(user.organization_id)

      assert_raise Postgrex.Error, ~r/Cannot modify KSeF-imported invoice data/, fn ->
        invoice
        |> Ecto.Changeset.change(%{seller: "Updated Seller"})
        |> Repo.update!()
      end
    end

    test "allows updating skip_invoicing for KSeF-imported invoice" do
      user = user_fixture()
      invoice = insert_ksef_cost_invoice!(user.organization_id)

      updated_invoice =
        invoice
        |> Ecto.Changeset.change(%{skip_invoicing: true})
        |> Repo.update!()

      assert updated_invoice.skip_invoicing
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
end
