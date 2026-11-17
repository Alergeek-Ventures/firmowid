defmodule Firmowid.Invoicing.InvoicingTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope

  defp scope_for(user) do
    %Scope{actor: user, tenant: user.member.organization_id}
  end

  describe "manual transaction disconnect" do
    test "connect_sales_invoice_transactions/3 rejects an empty transaction list" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      sales_invoice = seed_sales_disconnect_invoice!(organization_id)

      assert {:error, error} =
               Invoicing.connect_sales_invoice_transactions(
                 sales_invoice,
                 [],
                 scope: scope
               )

      assert Exception.message(error) =~ "Select at least one transaction."

      disconnected_invoice =
        Invoicing.get_sales_invoice!(sales_invoice.id, load: [:transactions], scope: scope)

      assert disconnected_invoice.transactions == []
    end

    test "disconnect_sales_invoice_transactions/3 rejects an empty transaction list" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      sales_invoice = seed_sales_disconnect_invoice!(organization_id)
      transaction = seed_sales_disconnect_transaction!(organization_id)

      {:ok, _invoice} =
        Invoicing.connect_sales_invoice_transactions(sales_invoice, [transaction.id], scope: scope)

      connected_invoice =
        Invoicing.get_sales_invoice!(sales_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]

      assert {:error, error} =
               Invoicing.disconnect_sales_invoice_transactions(
                 connected_invoice,
                 [],
                 scope: scope
               )

      assert Exception.message(error) =~ "Select at least one transaction."

      still_connected_invoice =
        Invoicing.get_sales_invoice!(sales_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(still_connected_invoice.transactions, & &1.id) == [transaction.id]
    end

    test "disconnect_all_sales_invoice_transactions/2 removes all linked transactions" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      sales_invoice = seed_sales_disconnect_invoice!(organization_id)
      transaction = seed_sales_disconnect_transaction!(organization_id)

      {:ok, _invoice} =
        Invoicing.connect_sales_invoice_transactions(sales_invoice, [transaction.id], scope: scope)

      connected_invoice =
        Invoicing.get_sales_invoice!(sales_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]

      assert {:ok, _invoice} =
               Invoicing.disconnect_all_sales_invoice_transactions(connected_invoice,
                 scope: scope
               )

      disconnected_invoice =
        Invoicing.get_sales_invoice!(sales_invoice.id, load: [:transactions], scope: scope)

      assert disconnected_invoice.transactions == []
    end

    test "disconnect_cost_invoice_transactions/3 rejects an empty transaction list" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      cost_invoice = seed_cost_disconnect_invoice!(organization_id)
      transaction = seed_cost_disconnect_transaction!(organization_id)

      {:ok, _invoice} =
        Invoicing.connect_cost_invoice_transactions(cost_invoice, [transaction.id], scope: scope)

      connected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]

      assert {:error, error} =
               Invoicing.disconnect_cost_invoice_transactions(
                 connected_invoice,
                 [],
                 scope: scope
               )

      assert Exception.message(error) =~ "Select at least one transaction."

      still_connected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(still_connected_invoice.transactions, & &1.id) == [transaction.id]
    end

    test "disconnect_all_cost_invoice_transactions/2 removes all linked transactions" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      cost_invoice = seed_cost_disconnect_invoice!(organization_id)
      transaction = seed_cost_disconnect_transaction!(organization_id)

      {:ok, _invoice} =
        Invoicing.connect_cost_invoice_transactions(cost_invoice, [transaction.id], scope: scope)

      connected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]

      assert {:ok, _invoice} =
               Invoicing.disconnect_all_cost_invoice_transactions(connected_invoice, scope: scope)

      disconnected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert disconnected_invoice.transactions == []
    end

    test "connect_cost_invoice_transactions/3 rejects an empty transaction list" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      cost_invoice = seed_cost_disconnect_invoice!(organization_id)

      assert {:error, error} =
               Invoicing.connect_cost_invoice_transactions(
                 cost_invoice,
                 [],
                 scope: scope
               )

      assert Exception.message(error) =~ "Select at least one transaction."

      disconnected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert disconnected_invoice.transactions == []
    end

    test "connect_sales_invoice_transactions/3 allows transactions with a different currency" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      sales_invoice = seed_sales_disconnect_invoice!(organization_id)

      transaction =
        seed_sales_disconnect_transaction!(organization_id, %{
          amount: Money.new!("EUR", Decimal.new("100.00"))
        })

      assert {:ok, _invoice} =
               Invoicing.connect_sales_invoice_transactions(sales_invoice, [transaction.id], scope: scope)

      connected_invoice =
        Invoicing.get_sales_invoice!(sales_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]
    end

    test "connect_cost_invoice_transactions/3 allows transactions with a different currency" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      cost_invoice = seed_cost_disconnect_invoice!(organization_id)

      transaction =
        seed_cost_disconnect_transaction!(organization_id, %{
          amount: Money.new!("EUR", Decimal.new("50.00"))
        })

      assert {:ok, _invoice} =
               Invoicing.connect_cost_invoice_transactions(cost_invoice, [transaction.id], scope: scope)

      connected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]
    end

    test "connect_sales_invoice_transactions/3 rejects missing transactions" do
      user = admin_fixture()
      scope = scope_for(user)
      organization_id = user.member.organization_id

      sales_invoice = seed_sales_disconnect_invoice!(organization_id)

      assert {:error, error} =
               Invoicing.connect_sales_invoice_transactions(sales_invoice, [Ash.UUID.generate()], scope: scope)

      assert Exception.message(error) =~ "transaction_ids"

      disconnected_invoice =
        Invoicing.get_sales_invoice!(sales_invoice.id, load: [:transactions], scope: scope)

      assert disconnected_invoice.transactions == []
    end
  end

  describe "get_logo_url/2" do
    test "returns nil when organization has no avatar blob" do
      user = admin_fixture()
      organization_id = user.member.organization_id

      assert Invoicing.get_logo_url(organization_id, scope: scope_for(user)) == nil
    end

    test "returns url when organization avatar blob is present" do
      user = admin_fixture()
      organization_id = user.member.organization_id
      scope = scope_for(user)

      blob = seed_blob!(organization_id, "org-logo.png", "org-logo-checksum")
      organization = Core.get_organization!(organization_id, scope: scope)

      # The seeded blob has no stored file to make the picture's copies from.
      Oban.Testing.with_testing_mode(:manual, fn ->
        Core.update_organization_avatar!(organization, %{avatar_blob_id: blob.id}, scope: scope)
      end)

      assert is_binary(Invoicing.get_logo_url(organization_id, scope: scope))
    end
  end

  defp seed_sales_disconnect_invoice!(organization_id) do
    Ash.Seed.seed!(SalesInvoice, %{
      invoice_number: "SI-DISCONNECT-#{System.unique_integer([:positive])}",
      buyer_full_name: "Disconnect Buyer",
      seller_display_name: "Our Company",
      sale_date: ~D[2024-06-10],
      issue_date: ~D[2024-06-10],
      due_date: ~D[2024-06-24],
      payment_method: :transfer,
      currency: "PLN",
      buyer_type: :company,
      organization_id: organization_id
    })
  end

  defp seed_sales_disconnect_transaction!(organization_id, attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    bank_account_id = bank_account_fixture_for_organization!(organization_id).id

    Ash.Seed.seed!(
      Transaction,
      Map.merge(
        %{
          transaction_id: "TX-DISCONNECT-SALES-#{unique}",
          internal_transaction_id: "INT-TX-DISCONNECT-SALES-#{unique}",
          creditor_name: "Disconnect Buyer",
          creditor_account: "ACC123",
          debtor_name: "Our Company",
          debtor_account: "ACC456",
          amount: Money.new!("PLN", Decimal.new("100.00")),
          booking_date: ~D[2024-06-10],
          value_date: ~D[2024-06-10],
          remittance_information_unstructured: "Payment for disconnect test sales invoice",
          bank_account_id: bank_account_id,
          organization_id: organization_id
        },
        attrs
      )
    )
  end

  defp seed_cost_disconnect_invoice!(organization_id) do
    unique = System.unique_integer([:positive])

    blob =
      seed_blob!(
        organization_id,
        "disconnect_cost_invoice_#{unique}.pdf",
        "disconnect_cost_checksum_#{unique}"
      )

    Ash.Seed.seed!(CostInvoice, %{
      seller: "Disconnect Supplier",
      seller_display_name: "Disconnect Supplier",
      invoice_identifier: "CI-DISCONNECT-#{unique}",
      description: "Disconnect test invoice",
      sale_date: ~D[2024-06-12],
      issue_date: ~D[2024-06-12],
      due_date: ~D[2024-06-26],
      amount: Money.new!("PLN", Decimal.new("-50.00")),
      skip_invoicing: false,
      organization_id: organization_id,
      blob_id: blob.id
    })
  end

  defp seed_cost_disconnect_transaction!(organization_id, attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    bank_account_id = bank_account_fixture_for_organization!(organization_id).id

    Ash.Seed.seed!(
      Transaction,
      Map.merge(
        %{
          transaction_id: "TX-DISCONNECT-COST-#{unique}",
          internal_transaction_id: "INT-TX-DISCONNECT-COST-#{unique}",
          creditor_name: "Our Company",
          creditor_account: "ACC456",
          debtor_name: "Disconnect Supplier",
          debtor_account: "ACC789",
          amount: Money.new!("PLN", Decimal.new("50.00")),
          booking_date: ~D[2024-06-12],
          value_date: ~D[2024-06-12],
          remittance_information_unstructured: "Payment for disconnect test cost invoice",
          bank_account_id: bank_account_id,
          organization_id: organization_id
        },
        attrs
      )
    )
  end

  # Seed a blob record without triggering S3 upload — tests only need a DB record with an id.
  defp seed_blob!(organization_id, filename, checksum) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/path/#{filename}",
      blob_checksum: checksum,
      original_filename: filename,
      organization_id: organization_id
    })
  end
end
