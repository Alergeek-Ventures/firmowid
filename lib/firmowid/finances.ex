defmodule Firmowid.Finances do
  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.Finances.ImportedTransaction
  alias Firmowid.Finances.BankAccount

  def list_bank_accounts(organization_id) do
    Repo.all(BankAccount, organization_id: organization_id)
  end

  def get_bank_account!(id, organization_id),
    do: Repo.get!(BankAccount, id, organization_id: organization_id)

  def create_bank_account(attrs \\ %{}) do
    %BankAccount{}
    |> BankAccount.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id]},
      conflict_target: [:iban, :organization_id]
    )
  end

  def update_bank_account(%BankAccount{} = bank_account, attrs) do
    bank_account
    |> BankAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_bank_account(%BankAccount{} = bank_account) do
    Repo.delete(bank_account)
  end

  def list_imported_transactions(organization_id, from \\ nil, to \\ nil, opts \\ []) do
    if Keyword.get(opts, :only_costs) == true do
      Repo.all(
        if from == nil and to == nil do
          from(t in ImportedTransaction, where: t.transaction_amount < 0.0)
        else
          from t in ImportedTransaction,
            where:
              t.value_date >= ^from and t.value_date <= ^to and
                t.transaction_amount < 0.0
        end,
        organization_id: organization_id
      )
    else
      Repo.all(
        if from == nil and to == nil do
          from(t in ImportedTransaction)
        else
          from t in ImportedTransaction,
            where: t.value_date >= ^from and t.value_date <= ^to
        end,
        organization_id: organization_id
      )
    end
    |> Repo.preload(:document_transactions, organization_id: organization_id)
    |> Enum.map(fn t ->
      Map.merge(t, %{
        amount:
          Money.new(
            t.transaction_currency,
            t.transaction_amount
          )
      })
    end)
  end

  def list_unmatched_imported_transactions(organization_id) do
    # all transactions that have skip_invoicing set to false (so we match for
    # them)
    # and don't have any document_transactions (so not matched yet)
    from(t in ImportedTransaction,
      left_join: dt in assoc(t, :document_transactions),
      where: not t.skip_invoicing,
      where: is_nil(dt.id)
    )
    |> Repo.all(organization_id: organization_id)
  end

  def get_imported_transaction!(organization_id, transaction_id) do
    transaction =
      Repo.get!(ImportedTransaction, transaction_id, organization_id: organization_id)
      |> Repo.preload(:bank_account, organization_id: organization_id)
      |> Repo.preload(:document_transactions, organization_id: organization_id)

    Map.merge(transaction, %{
      amount:
        Money.new(
          transaction.transaction_currency,
          transaction.transaction_amount
        )
    })
  end

  def create_or_update_imported_transaction(attrs \\ %{}) do
    %ImportedTransaction{}
    |> ImportedTransaction.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:internal_transaction_id, :organization_id]
    )
  end

  def update_imported_transaction(organization_id, imported_transaction_id, attrs) do
    changeset =
      get_imported_transaction!(organization_id, imported_transaction_id)
      |> ImportedTransaction.changeset(attrs)

    Repo.update!(changeset)
  end

  def delete_imported_transaction(%ImportedTransaction{} = imported_transaction) do
    Repo.delete(imported_transaction)
  end

  def change_imported_transaction(%ImportedTransaction{} = imported_transaction, attrs \\ %{}) do
    ImportedTransaction.changeset(imported_transaction, attrs)
  end
end
