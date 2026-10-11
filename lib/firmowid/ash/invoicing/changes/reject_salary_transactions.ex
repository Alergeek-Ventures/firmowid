defmodule Firmowid.Ash.Invoicing.Changes.RejectSalaryTransactions do
  @moduledoc "Prevents manual and automatic invoice matching from reusing a salary payment."

  use Ash.Resource.Change
  use Gettext, backend: FirmowidWeb.Core.Gettext

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Scope

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      ids = Ash.Changeset.get_argument(changeset, :transaction_ids)
      scope = Scope.new!(context.actor, context.tenant)

      case Finances.list_transactions!(%{ids: ids, salary_assigned: true}, scope: scope) do
        [] ->
          changeset

        _payments ->
          Ash.Changeset.add_error(changeset,
            field: :transaction_ids,
            message: gettext("A salary payment cannot be linked to an invoice.")
          )
      end
    end)
  end
end
