defmodule Firmowid.Finances.ExpectedTransaction.Changes.ValidateTransactionAvailability do
  @moduledoc """
  Lets an expectation be fulfilled only by bank transactions matched to nothing but expectations:
  a transaction already paying an invoice or a salary cannot also fulfil an expectation.
  """

  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Finances
  alias Firmowid.Scope

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      ids = Ash.Changeset.get_argument(changeset, :transaction_ids)

      available =
        %{ids: ids}
        |> Finances.list_transactions!(
          query: [lock: :for_update, sort: [id: :asc]],
          load: [:expectation_matchable?],
          scope: Scope.new!(context.actor, context.tenant)
        )
        |> Enum.filter(& &1.expectation_matchable?)

      if length(available) == length(Enum.uniq(ids)) do
        changeset
      else
        Ash.Changeset.add_error(changeset,
          field: :transaction_ids,
          message: gettext_noop("Could not link this transaction to the expected transaction.")
        )
      end
    end)
  end
end
