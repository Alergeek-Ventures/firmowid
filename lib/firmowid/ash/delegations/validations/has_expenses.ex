defmodule Firmowid.Ash.Delegations.Validations.HasExpenses do
  @moduledoc "Requires at least one expense before a delegation can be completed."

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    case Ash.load(changeset.data, expense_loads(), actor: context.actor, tenant: context.tenant) do
      {:ok, delegation} ->
        if has_expenses?(delegation),
          do: :ok,
          else: {:error, "Dodaj przynajmniej jeden dokument."}

      {:error, error} ->
        {:error, error}
    end
  end

  defp expense_loads, do: [:expenses]

  defp has_expenses?(delegation) do
    delegation.expenses != []
  end
end
