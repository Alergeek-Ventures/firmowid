defmodule Firmowid.Finances do
  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.Finances.Transaction
  alias Firmowid.Finances.BankAccount

  @doc """
    This shouldn't be used in "userland" - only in "private" workers.
    Please, be careful!
  """
  def get_bank_accounts_for_sync() do
    query =
      from ba in BankAccount,
        where: not is_nil(ba.gocardless_id)

    query
    |> Repo.all(skip_organization_id: true)
  end

  @transaction_broadcast_topic "transaction_broadcast_topic"

  def subscribe_transaction_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@transaction_broadcast_topic}:#{organization_id}"
    )
  end

  def broadcast_transaction_list_updated(organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@transaction_broadcast_topic}:#{organization_id}",
      :transaction_list_updated
    )
  end

  def list_bank_accounts() do
    BankAccount
    |> Repo.all()
    |> Repo.preload(:requisition)
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

  def make_account_default(bank_account_id) do
    bank_account = Repo.get!(BankAccount, bank_account_id)

    Repo.transaction(fn ->
      Repo.update_all(
        from(ba in BankAccount,
          where: ba.currency == ^bank_account.currency
        ),
        set: [is_default: false]
      )

      update_bank_account(bank_account, %{is_default: true})
    end)
  end

  def delete_bank_account(bank_account_id) do
    # TODO: dangling requisitions should be deleted!
    # not done yet, maybe via a worker?

    Repo.get!(BankAccount, bank_account_id)
    |> Repo.delete()
  end

  def list_transactions(organization_id, from \\ nil, to \\ nil, opts \\ []) do
    if Keyword.get(opts, :only_costs) == true do
      Repo.all(
        if from == nil and to == nil do
          from(t in Transaction, where: t.transaction_amount < 0.0)
        else
          from t in Transaction,
            where:
              t.value_date >= ^from and t.value_date <= ^to and
                t.transaction_amount < 0.0
        end,
        organization_id: organization_id
      )
    else
      Repo.all(
        if from == nil and to == nil do
          from(t in Transaction)
        else
          from t in Transaction,
            where: t.value_date >= ^from and t.value_date <= ^to
        end,
        organization_id: organization_id
      )
    end
    |> Repo.preload(:cost_invoices_transactions, organization_id: organization_id)
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

  def list_unmatched_transactions(organization_id) do
    # all transactions that have skip_invoicing set to false (so we match for
    # them)
    # and don't have any cost_invoices_transactions (so not matched yet)
    from(t in Transaction,
      left_join: dt in assoc(t, :cost_invoices_transactions),
      where: t.transaction_amount <= 0.0,
      where: not t.skip_invoicing,
      where: is_nil(dt.id)
    )
    |> Repo.all(organization_id: organization_id)
  end

  def get_transaction!(organization_id, transaction_id) do
    transaction =
      Repo.get!(Transaction, transaction_id, organization_id: organization_id)
      |> Repo.preload(:bank_account, organization_id: organization_id)
      |> Repo.preload(:cost_invoices_transactions, organization_id: organization_id)

    Map.merge(transaction, %{
      amount:
        Money.new(
          transaction.transaction_currency,
          transaction.transaction_amount
        )
    })
  end

  def toggle_skip_invoicing(:transaction, id) do
    transaction = Repo.get!(Transaction, id)

    transaction
    |> Ecto.Changeset.change(skip_invoicing: !transaction.skip_invoicing)
    |> Repo.update!()

    broadcast_transaction_list_updated(transaction.organization_id)
  end

  def create_or_update_transaction(attrs \\ %{}) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Repo.insert!(
        on_conflict: {:replace_all_except, [:id, :skip_invoicing, :inserted_at]},
        conflict_target: [:internal_transaction_id, :organization_id]
      )

    broadcast_transaction_list_updated(transaction.organization_id)
  end

  def update_transaction(organization_id, transaction_id, attrs) do
    changeset =
      get_transaction!(organization_id, transaction_id)
      |> Transaction.changeset(attrs)

    Repo.update!(changeset)
  end

  def delete_transaction(%Transaction{} = transaction) do
    Repo.delete(transaction)
  end

  def change_transaction(%Transaction{} = transaction, attrs \\ %{}) do
    Transaction.changeset(transaction, attrs)
  end
end
