defmodule Firmowid.FinancesTest do
  use Firmowid.DataCase

  alias Firmowid.Finances

  describe "bank_accounts" do
    alias Firmowid.Finances.BankAccount

    import Firmowid.FinancesFixtures

    @invalid_attrs %{iban: nil}

    test "list_bank_accounts/0 returns all bank_accounts" do
      bank_account = bank_account_fixture()
      assert Finances.list_bank_accounts() == [bank_account]
    end

    test "get_bank_account!/1 returns the bank_account with given id" do
      bank_account = bank_account_fixture()
      assert Finances.get_bank_account!(bank_account.id) == bank_account
    end

    test "create_bank_account/1 with valid data creates a bank_account" do
      valid_attrs = %{iban: "some iban"}

      assert {:ok, %BankAccount{} = bank_account} = Finances.create_bank_account(valid_attrs)
      assert bank_account.iban == "some iban"
    end

    test "create_bank_account/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Finances.create_bank_account(@invalid_attrs)
    end

    test "update_bank_account/2 with valid data updates the bank_account" do
      bank_account = bank_account_fixture()
      update_attrs = %{iban: "some updated iban"}

      assert {:ok, %BankAccount{} = bank_account} = Finances.update_bank_account(bank_account, update_attrs)
      assert bank_account.iban == "some updated iban"
    end

    test "update_bank_account/2 with invalid data returns error changeset" do
      bank_account = bank_account_fixture()
      assert {:error, %Ecto.Changeset{}} = Finances.update_bank_account(bank_account, @invalid_attrs)
      assert bank_account == Finances.get_bank_account!(bank_account.id)
    end

    test "delete_bank_account/1 deletes the bank_account" do
      bank_account = bank_account_fixture()
      assert {:ok, %BankAccount{}} = Finances.delete_bank_account(bank_account)
      assert_raise Ecto.NoResultsError, fn -> Finances.get_bank_account!(bank_account.id) end
    end

    test "change_bank_account/1 returns a bank_account changeset" do
      bank_account = bank_account_fixture()
      assert %Ecto.Changeset{} = Finances.change_bank_account(bank_account)
    end
  end

  describe "imported_transactions" do
    alias Firmowid.Finances.ImportedTransaction

    import Firmowid.FinancesFixtures

    @invalid_attrs %{transaction_id: nil, debtor_name: nil, debtor_account: nil, transaction_amount: nil, transaction_currency: nil, bank_transaction_code: nil, booking_date: nil, value_date: nil, remittance_information_unstructured: nil}

    test "list_imported_transactions/0 returns all imported_transactions" do
      imported_transaction = imported_transaction_fixture()
      assert Finances.list_imported_transactions() == [imported_transaction]
    end

    test "get_imported_transaction!/1 returns the imported_transaction with given id" do
      imported_transaction = imported_transaction_fixture()
      assert Finances.get_imported_transaction!(imported_transaction.id) == imported_transaction
    end

    test "create_imported_transaction/1 with valid data creates a imported_transaction" do
      valid_attrs = %{transaction_id: "some transaction_id", debtor_name: "some debtor_name", debtor_account: "some debtor_account", transaction_amount: 120.5, transaction_currency: "some transaction_currency", bank_transaction_code: "some bank_transaction_code", booking_date: ~D[2024-07-13], value_date: ~D[2024-07-13], remittance_information_unstructured: "some remittance_information_unstructured"}

      assert {:ok, %ImportedTransaction{} = imported_transaction} = Finances.create_imported_transaction(valid_attrs)
      assert imported_transaction.transaction_id == "some transaction_id"
      assert imported_transaction.debtor_name == "some debtor_name"
      assert imported_transaction.debtor_account == "some debtor_account"
      assert imported_transaction.transaction_amount == 120.5
      assert imported_transaction.transaction_currency == "some transaction_currency"
      assert imported_transaction.bank_transaction_code == "some bank_transaction_code"
      assert imported_transaction.booking_date == ~D[2024-07-13]
      assert imported_transaction.value_date == ~D[2024-07-13]
      assert imported_transaction.remittance_information_unstructured == "some remittance_information_unstructured"
    end

    test "create_imported_transaction/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Finances.create_imported_transaction(@invalid_attrs)
    end

    test "update_imported_transaction/2 with valid data updates the imported_transaction" do
      imported_transaction = imported_transaction_fixture()
      update_attrs = %{transaction_id: "some updated transaction_id", debtor_name: "some updated debtor_name", debtor_account: "some updated debtor_account", transaction_amount: 456.7, transaction_currency: "some updated transaction_currency", bank_transaction_code: "some updated bank_transaction_code", booking_date: ~D[2024-07-14], value_date: ~D[2024-07-14], remittance_information_unstructured: "some updated remittance_information_unstructured"}

      assert {:ok, %ImportedTransaction{} = imported_transaction} = Finances.update_imported_transaction(imported_transaction, update_attrs)
      assert imported_transaction.transaction_id == "some updated transaction_id"
      assert imported_transaction.debtor_name == "some updated debtor_name"
      assert imported_transaction.debtor_account == "some updated debtor_account"
      assert imported_transaction.transaction_amount == 456.7
      assert imported_transaction.transaction_currency == "some updated transaction_currency"
      assert imported_transaction.bank_transaction_code == "some updated bank_transaction_code"
      assert imported_transaction.booking_date == ~D[2024-07-14]
      assert imported_transaction.value_date == ~D[2024-07-14]
      assert imported_transaction.remittance_information_unstructured == "some updated remittance_information_unstructured"
    end

    test "update_imported_transaction/2 with invalid data returns error changeset" do
      imported_transaction = imported_transaction_fixture()
      assert {:error, %Ecto.Changeset{}} = Finances.update_imported_transaction(imported_transaction, @invalid_attrs)
      assert imported_transaction == Finances.get_imported_transaction!(imported_transaction.id)
    end

    test "delete_imported_transaction/1 deletes the imported_transaction" do
      imported_transaction = imported_transaction_fixture()
      assert {:ok, %ImportedTransaction{}} = Finances.delete_imported_transaction(imported_transaction)
      assert_raise Ecto.NoResultsError, fn -> Finances.get_imported_transaction!(imported_transaction.id) end
    end

    test "change_imported_transaction/1 returns a imported_transaction changeset" do
      imported_transaction = imported_transaction_fixture()
      assert %Ecto.Changeset{} = Finances.change_imported_transaction(imported_transaction)
    end
  end
end
