defmodule Firmowid.Ash.Finances.Changes.ConnectSalary do
  @moduledoc "Validates a salary assignment against current tenant-owned payroll and transaction data."

  use Ash.Resource.Change
  use Gettext, backend: FirmowidWeb.Core.Gettext

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Payroll.SalaryMatching
  alias Firmowid.Ash.Scope

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      scope = Scope.new!(context.actor, context.tenant)
      user_id = Ash.Changeset.get_attribute(changeset, :salary_user_id)
      month = Ash.Changeset.get_attribute(changeset, :salary_month)

      transaction =
        Finances.get_transaction!(changeset.data.id,
          load: [:direction, :bank_account, :has_salary?, :cost_invoices, :sales_invoices],
          scope: scope
        )

      if valid_assignment?(transaction, user_id, month, scope) do
        changeset
      else
        Ash.Changeset.add_error(changeset,
          field: :salary_month,
          message: gettext("The salary cannot be assigned to this transaction.")
        )
      end
    end)
  end

  defp valid_assignment?(transaction, user_id, %Date{day: 1} = month, scope) when is_binary(user_id) do
    summary = SalaryMatching.summary(user_id, month, scope)

    SalaryMatching.eligible?(transaction) and Date.compare(month, transaction.booking_date) != :gt and
      not is_nil(summary) and
      transaction.amount
      |> Money.to_decimal()
      |> Decimal.abs()
      |> SalaryMatching.within_tolerance?(Money.to_decimal(summary.expected_amount))
  end

  defp valid_assignment?(_transaction, _user_id, _month, _scope), do: false
end
