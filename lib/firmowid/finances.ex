defmodule Firmowid.Finances do
  import Paradex, only: [~>: 2]
  import Ecto.Query, warn: false

  alias Firmowid.CostInvoices.CostInvoicesTransactions
  alias Firmowid.SalesInvoices.SalesInvoicesTransactions
  alias Firmowid.Repo

  alias Firmowid.Finances.Transaction
  alias Firmowid.Finances.BankAccount

  @behaviour Bodyguard.Policy
  def authorize(:create_bank_account, %{role: :admin}, _), do: true
  def authorize(:read_bank_accounts, %{role: :admin}, _), do: true

  def authorize(action, %{role: :admin, organization_id: org_id}, %{
        organization_id: org_id
      })
      when action in [:read_bank_account, :update_bank_account, :delete_bank_account],
      do: true

  def authorize(_, _, _), do: false

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

  def get_bank_account!(id),
    do: Repo.get!(BankAccount, id)

  def create_bank_account(attrs \\ %{}) do
    %BankAccount{}
    |> BankAccount.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id]},
      conflict_target: [:iban, :organization_id]
    )
  end

  def create_manual_bank_account(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:institution_name, "Manual")
      |> Map.put(:gocardless_id, nil)
      |> Map.put(:institution_id, nil)
      |> Map.put(:requisition_id, nil)

    create_bank_account(attrs)
  end

  def update_bank_account(%BankAccount{} = bank_account, attrs) do
    bank_account
    |> BankAccount.changeset(attrs)
    |> Repo.update()
  end

  def rename_bank_account(bank_account_id, new_name) do
    bank_account = Repo.get!(BankAccount, bank_account_id)
    update_bank_account(bank_account, %{name: new_name})
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

  def list_transactions(from, to) do
    query =
      from t in Transaction,
        where: t.booking_date >= ^from and t.booking_date <= ^to,
        order_by: [desc: t.booking_date]

    query
    |> Repo.all()
    |> Repo.preload(:cost_invoices_transactions)
    |> Repo.preload(:sales_invoices_transactions)
  end

  def search_transactions(params \\ %{}) do
    query = Map.get(params, :query)
    only_unmatched = Map.get(params, :only_unmatched, true)
    currency = Map.get(params, :currency)
    amount_gt = Map.get(params, :amount_gt)
    amount_lt = Map.get(params, :amount_lt)
    date_from = Map.get(params, :date_from)
    date_to = Map.get(params, :date_to)

    base_query =
      from(Transaction, as: :transaction)
      |> preload([:cost_invoices_transactions, :sales_invoices_transactions])

    base_query =
      if only_unmatched do
        base_query
        |> where(
          [t],
          union(
            from(ci in CostInvoicesTransactions,
              where: parent_as(:transaction).id == ci.transaction_id
            ),
            ^from(si in SalesInvoicesTransactions,
              where: parent_as(:transaction).id == si.transaction_id
            )
          )
          |> exists() == false
        )
        |> where([t], t.skip_invoicing == false)
      else
        base_query
      end

    base_query =
      if not is_nil(currency) do
        base_query
        |> where([t], t.transaction_currency == ^currency)
      else
        base_query
      end

    base_query =
      if not is_nil(amount_gt) do
        where(base_query, [t], t.transaction_amount >= ^amount_gt)
      else
        base_query
      end

    base_query =
      if not is_nil(amount_lt) do
        where(base_query, [t], t.transaction_amount <= ^amount_lt)
      else
        base_query
      end

    base_query =
      if not is_nil(date_from) do
        where(base_query, [t], t.booking_date >= ^date_from or t.value_date >= ^date_from)
      else
        base_query
      end

    base_query =
      if not is_nil(date_to) do
        where(base_query, [t], t.booking_date <= ^date_to or t.value_date <= ^date_to)
      else
        base_query
      end

    base_query =
      if not is_nil(query) do
        base_query
        |> where(
          [t],
          t.debtor_name ~> ^query or
            t.creditor_name ~> ^query or
            t.remittance_information_unstructured ~> ^query or
            t.transaction_currency ~> ^query
        )
        |> order_by([t], fragment("paradedb.score(?) DESC", t.id))
      else
        base_query
        |> order_by([t], desc: t.booking_date)
      end

    base_query
    |> limit(50)
    |> Repo.all()
  end

  def list_unmatched_transactions(from, to) do
    # all transactions that have skip_invoicing set to false
    # (so we match for them)
    # and don't have any cost_invoices_transactions (so not matched yet)
    from(t in Transaction,
      left_join: ci in assoc(t, :cost_invoices_transactions),
      left_join: si in assoc(t, :sales_invoices_transactions),
      where: t.skip_invoicing == false,
      where: is_nil(ci.id),
      where: is_nil(si.id),
      where: t.booking_date >= ^from and t.booking_date <= ^to,
      order_by: [desc: t.booking_date]
    )
    |> Repo.all()
    |> Repo.preload(:cost_invoices_transactions)
    |> Repo.preload(:sales_invoices_transactions)
  end

  def get_transaction!(transaction_id) do
    transaction =
      Repo.get!(Transaction, transaction_id)
      |> Repo.preload(:bank_account)
      |> Repo.preload(:cost_invoices_transactions)

    Map.merge(transaction, %{
      amount:
        Money.new(
          transaction.transaction_currency,
          transaction.transaction_amount
        )
    })
  end

  def get_transactions!(ids) do
    Transaction
    |> where([t], t.id in ^ids)
    |> Repo.all()
    |> Enum.map(fn transaction ->
      Map.merge(transaction, %{
        amount: Money.new(transaction.transaction_currency, transaction.transaction_amount)
      })
    end)
  end

  def toggle_skip_invoicing(id) do
    transaction = Repo.get!(Transaction, id)

    transaction
    |> Ecto.Changeset.change(skip_invoicing: !transaction.skip_invoicing)
    |> Repo.update!()

    broadcast_transaction_list_updated(transaction.organization_id)
  end

  def create_or_update_transactions(transactions) do
    transactions =
      transactions
      |> Enum.map(fn transaction ->
        Map.merge(transaction, %{
          id: UUIDv7.autogenerate(),
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      end)

    Transaction
    |> Repo.insert_all(transactions,
      on_conflict: {:replace_all_except, [:id, :skip_invoicing, :inserted_at]},
      conflict_target: [:internal_transaction_id, :organization_id]
    )

    case transactions |> List.first() do
      nil ->
        nil

      transaction ->
        organization_id = transaction |> Map.get(:organization_id)
        broadcast_transaction_list_updated(organization_id)
    end
  end

  def update_transaction(transaction_id, attrs) do
    changeset =
      get_transaction!(transaction_id)
      |> Transaction.changeset(attrs)

    Repo.update!(changeset)
  end

  def delete_transaction(%Transaction{} = transaction) do
    Repo.delete(transaction)
  end

  def change_transaction(%Transaction{} = transaction, attrs \\ %{}) do
    Transaction.changeset(transaction, attrs)
  end

  def list_transactions_by_ids(ids, date_from \\ nil, date_to \\ nil) do
    query =
      Transaction
      |> where([t], t.id in ^ids)

    query =
      cond do
        date_from && date_to ->
          query |> where([t], t.booking_date >= ^date_from and t.booking_date <= ^date_to)

        date_from ->
          query |> where([t], t.booking_date >= ^date_from)

        date_to ->
          query |> where([t], t.booking_date <= ^date_to)

        true ->
          query
      end

    Repo.all(query)
  end
end
