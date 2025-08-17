defmodule Firmowid.FinancesSearchTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Repo

  describe "search_transactions/1" do
    test "returns matching transactions using BM25 search" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      # Insert test transactions directly – we bypass the changeset on purpose to keep the
      # setup minimal and avoid the many required fields. Only the columns that matter for the
      # search and multi-tenancy are provided.
      transaction1 =
        Repo.insert!(%Transaction{
          debtor_name: "Acme Corp",
          creditor_name: "John Doe",
          remittance_information_unstructured: "Invoice #123",
          transaction_currency: "USD",
          organization_id: organization_id
        })

      _transaction2 =
        Repo.insert!(%Transaction{
          debtor_name: "Another Company",
          creditor_name: "Jane Smith",
          remittance_information_unstructured: "Payment for services_user",
          transaction_currency: "USD",
          organization_id: organization_id
        })

      # Run the search
      [found_transaction] = Finances.search_transactions(%{query: "Acme", currency: "USD"})

      assert found_transaction.id == transaction1.id
      assert found_transaction.debtor_name == "Acme Corp"
    end

    test "returns empty list when no matches found" do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      _ =
        Repo.insert!(%Transaction{
          debtor_name: "Some Company",
          creditor_name: "Someone",
          remittance_information_unstructured: "Some payment",
          transaction_currency: "USD",
          organization_id: organization_id
        })

      results = Finances.search_transactions(%{query: "NonExistent"})
      assert results == []
    end

    test "does not find transactions across organizations" do
      # Create user and transaction in org1
      user1 = user_fixture()
      org1_id = user1.organization_id

      tx1 =
        Repo.insert!(%Transaction{
          debtor_name: "Org1 Debtor",
          creditor_name: "Org1 Creditor",
          remittance_information_unstructured: "UniqueOrg1",
          organization_id: org1_id,
          transaction_currency: "PLN"
        })

      # Create user and transaction in org2
      user2 = user_fixture()
      org2_id = user2.organization_id

      tx2 =
        Repo.insert!(%Transaction{
          debtor_name: "Org2 Debtor",
          creditor_name: "Org2 Creditor",
          remittance_information_unstructured: "UniqueOrg2",
          organization_id: org2_id,
          transaction_currency: "PLN"
        })

      # Set org context to org1, search for org2's transaction
      Repo.put_org_id(org1_id)
      results = Finances.search_transactions(%{query: "UniqueOrg2"})
      assert results == []

      # Set org context to org2, search for org1's transaction
      Repo.put_org_id(org2_id)
      results = Finances.search_transactions(%{query: "UniqueOrg1"})
      assert results == []

      # Set org context to org1, search for org1's transaction
      Repo.put_org_id(org1_id)
      results = Finances.search_transactions(%{query: "UniqueOrg1"})
      assert Enum.map(results, & &1.id) == [tx1.id]

      # Set org context to org2, search for org2's transaction
      Repo.put_org_id(org2_id)
      results = Finances.search_transactions(%{query: "UniqueOrg2"})
      assert Enum.map(results, & &1.id) == [tx2.id]
    end
  end

  describe "search_transactions/1 with amount and date filters" do
    setup do
      _user = user_fixture()
      organization_id = Repo.get_org_id()

      t1 =
        Repo.insert!(%Transaction{
          debtor_name: "Alpha",
          transaction_amount: 100,
          booking_date: ~D[2024-01-01],
          value_date: ~D[2024-01-02],
          organization_id: organization_id,
          transaction_currency: "PLN"
        })

      t2 =
        Repo.insert!(%Transaction{
          debtor_name: "Beta",
          transaction_amount: 200,
          booking_date: ~D[2024-02-01],
          value_date: ~D[2024-02-02],
          organization_id: organization_id,
          transaction_currency: "PLN"
        })

      t3 =
        Repo.insert!(%Transaction{
          debtor_name: "Gamma",
          transaction_amount: 300,
          booking_date: ~D[2024-03-01],
          value_date: ~D[2024-03-02],
          organization_id: organization_id,
          transaction_currency: "PLN"
        })

      %{t1: t1, t2: t2, t3: t3}
    end

    test "filters by amount_gt and amount_lt", %{t1: _t1, t2: t2, t3: _t3} do
      results = Finances.search_transactions(%{amount_gt: 150, amount_lt: 250})
      assert Enum.map(results, & &1.id) == [t2.id]
    end

    test "filters by date_from and date_to", %{
      t1: t1,
      t2: t2,
      t3: t3
    } do
      # Should match t2 and t3 (booking_date or value_date in range)
      results =
        Finances.search_transactions(%{date_from: ~D[2024-02-01], date_to: ~D[2024-03-01]})

      ids = Enum.map(results, & &1.id)
      assert t2.id in ids
      assert t3.id in ids
      refute t1.id in ids
    end

    test "matches if either booking_date or value_date is in range", %{t1: t1, t2: _t2, t3: _t3} do
      # Only t1 has value_date in this range
      results =
        Finances.search_transactions(%{date_from: ~D[2024-01-02], date_to: ~D[2024-01-02]})

      assert Enum.map(results, & &1.id) == [t1.id]
    end
  end
end
