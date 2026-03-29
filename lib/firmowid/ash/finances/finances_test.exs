defmodule Firmowid.FinancesTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Finances.TransactionQueries
  alias Firmowid.BankData.Requisition
  alias Firmowid.Finances.BankAccount
  alias Firmowid.Finances.Transaction

  setup do
    user = user_fixture()
    organization_id = user.organization_id

    # Insert a dummy requisition
    {:ok, requisition} =
      %Requisition{
        id: Ecto.UUID.generate(),
        status: :accepted,
        organization_id: organization_id
      }
      |> Requisition.changeset(%{})
      |> Firmowid.Repo.insert()

    {:ok, bank_account} =
      %BankAccount{
        iban: "PL12345678901234567890123456",
        organization_id: organization_id,
        requisition_id: requisition.id
      }
      |> BankAccount.changeset(%{})
      |> Firmowid.Repo.insert()

    {:ok, bank_account: bank_account, organization_id: organization_id}
  end

  test "returns matched transactions with only_unmatched: false", %{
    bank_account: bank_account,
    organization_id: organization_id
  } do
    t =
      %Transaction{
        creditor_name: "Matched Skip",
        creditor_account: "PL333",
        debtor_name: "Jane Doe",
        debtor_account: "PL444",
        transaction_amount: Decimal.new("200.00"),
        transaction_currency: "PLN",
        booking_date: ~D[2024-01-02],
        value_date: ~D[2024-01-02],
        remittance_information_unstructured: "Test 2",
        skip_invoicing: true,
        bank_account_id: bank_account.id,
        organization_id: organization_id
      }
      |> Transaction.changeset(%{})
      |> Firmowid.Repo.insert!()

    results = TransactionQueries.search(%{only_unmatched: false})

    assert Enum.any?(results, &(&1.id == t.id))
  end

  test "returns only unmatched transactions with only_unmatched: true", %{
    bank_account: bank_account,
    organization_id: organization_id
  } do
    t =
      %Transaction{
        creditor_name: "Acme Sp. z o.o.",
        creditor_account: "PL111",
        debtor_name: "John Doe",
        debtor_account: "PL222",
        transaction_amount: Decimal.new("100.00"),
        transaction_currency: "PLN",
        booking_date: ~D[2024-01-01],
        value_date: ~D[2024-01-01],
        remittance_information_unstructured: "Test 1",
        skip_invoicing: false,
        bank_account_id: bank_account.id,
        organization_id: organization_id
      }
      |> Transaction.changeset(%{})
      |> Firmowid.Repo.insert!()

    results = TransactionQueries.search(%{only_matched: true})

    assert Enum.any?(results, &(&1.id == t.id))
  end

  test "filters by creditor_name", %{bank_account: bank_account, organization_id: organization_id} do
    t =
      %Transaction{
        creditor_name: "Acme Sp. z o.o.",
        creditor_account: "PL111",
        debtor_name: "John Doe",
        debtor_account: "PL222",
        transaction_amount: Decimal.new("100.00"),
        transaction_currency: "PLN",
        booking_date: ~D[2024-01-01],
        value_date: ~D[2024-01-01],
        remittance_information_unstructured: "Test 1",
        skip_invoicing: false,
        bank_account_id: bank_account.id,
        organization_id: organization_id
      }
      |> Transaction.changeset(%{})
      |> Firmowid.Repo.insert!()

    results =
      TransactionQueries.search(%{query: "Acme"})

    assert Enum.any?(results, &(&1.id == t.id))
  end
end
