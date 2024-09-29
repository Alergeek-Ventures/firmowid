defmodule Firmowid.Finances do
  @moduledoc """
  The Finances context.
  """

  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.Finances.BankAccount

  @doc """
  Returns the list of bank_accounts.

  ## Examples

      iex> list_bank_accounts()
      [%BankAccount{}, ...]

  """
  def list_bank_accounts(organization_id) do
    Repo.all(BankAccount, organization_id: organization_id)
  end

  @doc """
  Gets a single bank_account.

  Raises `Ecto.NoResultsError` if the Bank account does not exist.

  ## Examples

      iex> get_bank_account!(123)
      %BankAccount{}

      iex> get_bank_account!(456)
      ** (Ecto.NoResultsError)

  """
  def get_bank_account!(id, organization_id),
    do: Repo.get!(BankAccount, id, organization_id: organization_id)

  @doc """
  Creates a bank_account.

  ## Examples

      iex> create_bank_account(%{field: value})
      {:ok, %BankAccount{}}

      iex> create_bank_account(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_bank_account(attrs \\ %{}) do
    %BankAccount{}
    |> BankAccount.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a bank_account.

  ## Examples

      iex> update_bank_account(bank_account, %{field: new_value})
      {:ok, %BankAccount{}}

      iex> update_bank_account(bank_account, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_bank_account(%BankAccount{} = bank_account, attrs) do
    bank_account
    |> BankAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bank_account.

  ## Examples

      iex> delete_bank_account(bank_account)
      {:ok, %BankAccount{}}

      iex> delete_bank_account(bank_account)
      {:error, %Ecto.Changeset{}}

  """
  def delete_bank_account(%BankAccount{} = bank_account) do
    Repo.delete(bank_account)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bank_account changes.

  ## Examples

      iex> change_bank_account(bank_account)
      %Ecto.Changeset{data: %BankAccount{}}

  """
  def change_bank_account(%BankAccount{} = bank_account, attrs \\ %{}) do
    BankAccount.changeset(bank_account, attrs)
  end

  alias Firmowid.Finances.ImportedTransaction

  @doc """
  Returns the list of imported_transactions.

  ## Examples

      iex> list_imported_transactions()
      [%ImportedTransaction{}, ...]

  """
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

  @doc """
  Gets a single imported_transaction.

  Raises `Ecto.NoResultsError` if the Imported transaction does not exist.

  ## Examples

      iex> get_imported_transaction!(123)
      %ImportedTransaction{}

      iex> get_imported_transaction!(456)
      ** (Ecto.NoResultsError)

  """
  def get_imported_transaction!(organization_id, transaction_id) do
    transaction =
      Repo.get!(ImportedTransaction, transaction_id, organization_id: organization_id)
      |> Repo.preload(:bank_account)
      |> Repo.preload(:document_transactions)

    Map.merge(transaction, %{
      amount:
        Money.new(
          transaction.transaction_currency,
          transaction.transaction_amount
        )
    })
  end

  @doc """
  Creates a imported_transaction.

  ## Examples

      iex> create_imported_transaction(%{field: value})
      {:ok, %ImportedTransaction{}}

      iex> create_imported_transaction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_or_update_imported_transaction(attrs \\ %{}) do
    %ImportedTransaction{}
    |> ImportedTransaction.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:transaction_id, :organization_id]
    )
  end

  @doc """
  Updates a imported_transaction.

  ## Examples

      iex> update_imported_transaction(imported_transaction, %{field: new_value})
      {:ok, %ImportedTransaction{}}

      iex> update_imported_transaction(imported_transaction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_imported_transaction(organization_id, imported_transaction_id, attrs) do
    changeset =
      get_imported_transaction!(organization_id, imported_transaction_id)
      |> ImportedTransaction.changeset(attrs)

    Repo.update!(changeset)
  end

  @doc """
  Deletes a imported_transaction.

  ## Examples

      iex> delete_imported_transaction(imported_transaction)
      {:ok, %ImportedTransaction{}}

      iex> delete_imported_transaction(imported_transaction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_imported_transaction(%ImportedTransaction{} = imported_transaction) do
    Repo.delete(imported_transaction)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking imported_transaction changes.

  ## Examples

      iex> change_imported_transaction(imported_transaction)
      %Ecto.Changeset{data: %ImportedTransaction{}}

  """
  def change_imported_transaction(%ImportedTransaction{} = imported_transaction, attrs \\ %{}) do
    ImportedTransaction.changeset(imported_transaction, attrs)
  end
end
