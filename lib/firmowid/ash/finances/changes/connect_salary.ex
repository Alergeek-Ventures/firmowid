defmodule Firmowid.Ash.Finances.Changes.ConnectSalary do
  @moduledoc "Validates a salary assignment against current tenant-owned payroll and transaction data."

  use Ash.Resource.Change
  use Gettext, backend: FirmowidWeb.Core.Gettext

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Scope

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      scope = Scope.new!(context.actor, context.tenant)
      user_id = Ash.Changeset.get_attribute(changeset, :salary_user_id)
      month = Ash.Changeset.get_attribute(changeset, :salary_month)

      if valid_assignment?(changeset.data.id, user_id, month, scope) do
        changeset
      else
        Ash.Changeset.add_error(changeset,
          field: :salary_month,
          message: gettext("The salary cannot be assigned to this transaction.")
        )
      end
    end)
  end

  defp valid_assignment?(transaction_id, user_id, %Date{day: 1} = month, scope) when is_binary(user_id) do
    Finances.suggest_transaction_salaries!(
      transaction_id,
      %{salary_user_id: user_id, salary_month: month},
      scope: scope
    ) != []
  end

  defp valid_assignment?(_transaction_id, _user_id, _month, _scope), do: false
end
