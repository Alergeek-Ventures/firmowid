defmodule Firmowid.Delegations.Validations.HasExpenses do
  @moduledoc """
  Requires at least one expense before a delegation can be completed, unless a per diem or
  lump sum is due, which is enough to settle on its own.
  """

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Delegations.PerDiem

  @impl true
  def validate(changeset, _opts, context) do
    with {:ok, delegation} <-
           Ash.load(changeset.data, :expenses, actor: context.actor, tenant: context.tenant) do
      if delegation.expenses != [] or per_diem_due?(changeset),
        do: :ok,
        else: {:error, gettext_noop("Add at least one document.")}
    end
  end

  defp per_diem_due?(changeset) do
    {:ok, delegation} = Ash.Changeset.apply_attributes(changeset)

    case PerDiem.for_delegation(delegation) do
      nil -> false
      per_diem -> Money.positive?(per_diem.total)
    end
  end
end
