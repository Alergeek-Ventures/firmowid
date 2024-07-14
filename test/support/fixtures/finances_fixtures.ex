defmodule Firmowid.FinancesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Firmowid.Finances` context.
  """

  @doc """
  Generate a bank_account.
  """
  def bank_account_fixture(attrs \\ %{}) do
    {:ok, bank_account} =
      attrs
      |> Enum.into(%{
        iban: "some iban"
      })
      |> Firmowid.Finances.create_bank_account()

    bank_account
  end

  @doc """
  Generate a imported_transaction.
  """
  def imported_transaction_fixture(attrs \\ %{}) do
    {:ok, imported_transaction} =
      attrs
      |> Enum.into(%{
        bank_transaction_code: "some bank_transaction_code",
        booking_date: ~D[2024-07-13],
        debtor_account: "some debtor_account",
        debtor_name: "some debtor_name",
        remittance_information_unstructured: "some remittance_information_unstructured",
        transaction_amount: 120.5,
        transaction_currency: "some transaction_currency",
        transaction_id: "some transaction_id",
        value_date: ~D[2024-07-13]
      })
      |> Firmowid.Finances.create_imported_transaction()

    imported_transaction
  end
end
