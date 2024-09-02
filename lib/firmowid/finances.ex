defmodule Firmowid.Finances do
  @moduledoc """
  The Finances context.
  """

  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.Finances.BankAccount

  alias Akin

  @doc """
  Returns the list of bank_accounts.

  ## Examples

      iex> list_bank_accounts()
      [%BankAccount{}, ...]

  """
  def list_bank_accounts do
    Repo.all(BankAccount)
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
  def get_bank_account!(id), do: Repo.get!(BankAccount, id)

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
  def list_imported_transactions do
    Repo.all(ImportedTransaction)
    |> Enum.map(fn t ->
      Map.merge(t, %{
        amount:
          Money.from_float!(
            t.transaction_currency,
            t.transaction_amount
          )
      })
    end)
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
  def get_imported_transaction!(transaction_id) do
    transaction =
      Repo.get!(ImportedTransaction, transaction_id)
      |> Repo.preload(:bank_account)

    Map.merge(transaction, %{
      amount:
        Money.from_float!(
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
  def create_imported_transaction(attrs \\ %{}) do
    %ImportedTransaction{}
    |> ImportedTransaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a imported_transaction.

  ## Examples

      iex> update_imported_transaction(imported_transaction, %{field: new_value})
      {:ok, %ImportedTransaction{}}

      iex> update_imported_transaction(imported_transaction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_imported_transaction(%ImportedTransaction{} = imported_transaction, attrs) do
    imported_transaction
    |> ImportedTransaction.changeset(attrs)
    |> Repo.update()
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

  def get_potential_transactions(document) do
    # date range -> between issue_date and payment_deadline
    issue_date = document.issue_date |> Date.add(-1)
    payment_deadline = document.due_date |> Date.add(3)

    # amount - within 10% of total amount
    total_amount = -document.total_amount

    max_amount = total_amount * 0.9
    min_amount = total_amount * 1.1

    candidates =
      ImportedTransaction
      |> where([i], i.booking_date >= ^issue_date and i.booking_date <= ^payment_deadline)
      |> where([i], i.transaction_amount >= ^min_amount and i.transaction_amount <= ^max_amount)
      |> Repo.all()

    candidates =
      Enum.filter(candidates, fn candidate_transaction ->
        Akin.compare(
          candidate_transaction.creditor_name,
          document.seller
        ).jaro_winkler > 0.5
      end)

    candidates
  end
end
