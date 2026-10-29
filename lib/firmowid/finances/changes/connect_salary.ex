defmodule Firmowid.Finances.Changes.ConnectSalary do
  @moduledoc """
  Validates a salary assignment against current tenant-owned payroll and transaction data.

  Repeating an existing assignment succeeds without changes. The update only applies to a pending transaction
  or one already assigned to the same salary, so a concurrent assignment cannot be overwritten.
  """

  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  import Ash.Expr

  alias Firmowid.Finances
  alias Firmowid.Scope

  @impl true
  def change(changeset, _opts, context) do
    user_id = Ash.Changeset.get_attribute(changeset, :salary_user_id)
    month = Ash.Changeset.get_attribute(changeset, :salary_month)

    changeset
    |> Ash.Changeset.filter(updatable(user_id, month))
    |> Ash.Changeset.before_action(fn changeset ->
      scope = Scope.new!(context.actor, context.tenant)

      case conflict(changeset.data.id, user_id, month, scope) do
        nil -> changeset
        message -> Ash.Changeset.add_error(changeset, field: :salary_month, message: message)
      end
    end)
  end

  defp updatable(user_id, month) when is_binary(user_id) and is_struct(month, Date) do
    expr(reconciliation_status == :pending or (salary_user_id == ^user_id and salary_month == ^month))
  end

  defp updatable(_user_id, _month), do: expr(reconciliation_status == :pending)

  defp conflict(transaction_id, user_id, %Date{day: 1} = month, scope) when is_binary(user_id) do
    transaction = Finances.get_transaction!(transaction_id, scope: scope)

    cond do
      transaction.salary_user_id == user_id and transaction.salary_month == month ->
        nil

      transaction.salary_user_id ->
        gettext("The transaction already pays the salary of %{month}. Disconnect it first.",
          month: Date.to_iso8601(transaction.salary_month)
        )

      transaction.skip_invoicing ->
        gettext("The transaction is skipped. Restore it for matching first.")

      true ->
        transaction_id
        |> Finances.suggest_transaction_salaries!(
          %{salary_user_id: user_id, salary_month: month, submitted_hours_only?: false},
          scope: scope
        )
        |> reason_message(user_id, month, scope)
    end
  end

  defp conflict(_transaction_id, _user_id, _month, _scope),
    do: gettext("The salary cannot be assigned to this transaction.")

  defp reason_message(%{suggestions: [_ | _]}, _user_id, _month, _scope), do: nil

  defp reason_message(%{reason: :salaries_already_paid}, user_id, month, scope) do
    [paying] =
      Finances.list_transactions!(%{salary_user_id: user_id, salary_month: month}, scope: scope)

    gettext("The salary is already paid by transaction %{id}.", id: paying.id)
  end

  defp reason_message(%{reason: :not_outgoing_pln}, _user_id, _month, _scope),
    do: gettext("Only an outgoing PLN transfer can pay a salary.")

  defp reason_message(%{reason: :transaction_matched}, _user_id, _month, _scope),
    do: gettext("The transaction is already connected to an invoice or a salary. Disconnect it first.")

  defp reason_message(%{reason: :month_out_of_range}, _user_id, _month, _scope),
    do: gettext("The salary month must fall within six months before the transfer.")

  defp reason_message(%{reason: :no_salaries}, _user_id, _month, _scope),
    do: gettext("The employee has no salary rate in this month.")

  defp reason_message(%{reason: :amount_out_of_range}, _user_id, _month, _scope),
    do: gettext("The transfer amount differs from the expected salary by more than 20% (at least 1000 PLN).")
end
