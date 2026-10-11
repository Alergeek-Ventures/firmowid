defmodule Firmowid.Ash.Invoicing.Changes.ValidateTransactionAvailability do
  @moduledoc "Checks invoice connection eligibility owned by the transaction resource."

  use Ash.Resource.Change
  use Gettext, backend: FirmowidWeb.Core.Gettext

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Scope

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      ids = Ash.Changeset.get_argument(changeset, :transaction_ids)
      scope = Scope.new!(context.actor, context.tenant)

      available_ids =
        %{ids: ids}
        |> Finances.list_transactions!(load: [:invoice_matchable?], scope: scope)
        |> Enum.filter(& &1.invoice_matchable?)
        |> MapSet.new(& &1.id)

      if Enum.all?(ids, &MapSet.member?(available_ids, &1)) do
        changeset
      else
        Ash.Changeset.add_error(changeset,
          field: :transaction_ids,
          message: gettext("Could not connect this transaction to the invoice.")
        )
      end
    end)
  end
end
