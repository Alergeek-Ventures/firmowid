defmodule Firmowid.Delegations.Changes.PrepareDelegationCompletion do
  @moduledoc "Validates final expense data and derives evidence dates before completion."

  use Ash.Resource.Change

  alias Firmowid.Delegations.Changes.UpdateDetectedDelegationDates

  @impl true
  def change(changeset, _opts, context) do
    case Ash.load(changeset.data, [:expenses], actor: context.actor, tenant: context.tenant) do
      {:ok, delegation} -> prepare(changeset, delegation.expenses, context)
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp prepare(changeset, expenses, context) do
    expense_params = expense_params_by_id(Ash.Changeset.get_argument(changeset, :expenses))

    final_expenses =
      Enum.map(expenses, fn expense ->
        params =
          expense_params
          |> Map.get(to_string(expense.id), %{})
          |> Map.drop([:id, "id"])

        Ash.Changeset.for_update(expense, :complete, params,
          actor: context.actor,
          tenant: context.tenant
        )
      end)

    case Enum.find(final_expenses, &(not &1.valid?)) do
      nil ->
        expenses =
          Enum.map(final_expenses, fn expense_changeset ->
            {:ok, expense} = Ash.Changeset.apply_attributes(expense_changeset)
            expense
          end)

        Ash.Changeset.change_attributes(
          changeset,
          UpdateDetectedDelegationDates.detected_dates(changeset.data, expenses)
        )

      invalid_changeset ->
        Ash.Changeset.add_error(changeset, invalid_changeset.errors)
    end
  end

  defp expense_params_by_id(expenses) do
    Map.new(expenses, fn params -> {to_string(params[:id] || params["id"]), params} end)
  end
end
