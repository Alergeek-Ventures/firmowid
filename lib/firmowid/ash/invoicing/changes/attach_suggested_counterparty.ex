defmodule Firmowid.Ash.Invoicing.Changes.AttachSuggestedCounterparty do
  @moduledoc """
  Resolves the selected counterparty and applies the requested attachment.

  Atomic eligibility checks are enforced in the action-level write filter.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.Invoicing.Counterparty

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      counterparty_id = Ash.Changeset.get_argument(changeset, :counterparty_id)
      tenant = changeset.tenant
      actor = context.actor

      case get_counterparty(counterparty_id, actor, tenant) do
        {:ok, %Counterparty{} = counterparty} ->
          Ash.Changeset.force_change_attribute(changeset, :counterparty_id, counterparty.id)

        {:ok, nil} ->
          Ash.Changeset.add_error(changeset, not_found_error())

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp get_counterparty(counterparty_id, actor, tenant) do
    Counterparty
    |> Ash.Query.for_read(:by_id, %{id: counterparty_id}, actor: actor, tenant: tenant)
    |> Ash.read_one(actor: actor, tenant: tenant)
  end

  defp not_found_error do
    InvalidAttribute.exception(field: :counterparty_id, message: "Nie znaleziono kontrahenta")
  end
end
