defmodule Firmowid.Ash.Invoicing.Changes.RecordManualMatch do
  @moduledoc """
  Records an invoice-transaction connection change as manual in the event log, with the
  acting user, unless the caller already supplied match metadata (automatic matching does).

  With `current_transactions?: true` it also records the IDs of the currently connected
  transactions, for actions that disconnect all of them without listing them.
  """

  use Ash.Resource.Change

  alias Firmowid.Ash.Scope

  @impl true
  def change(changeset, opts, context) do
    if Map.has_key?(changeset.context, :ash_events_metadata) do
      changeset
    else
      metadata = %{source: :manual, matched_by: matcher_id(context.actor)}

      metadata =
        if opts[:current_transactions?] do
          invoice =
            Ash.load!(changeset.data, [:transactions], scope: Scope.new!(context.actor, context.tenant))

          Map.put(metadata, :transaction_ids, Enum.map(invoice.transactions, & &1.id))
        else
          metadata
        end

      Ash.Changeset.set_context(changeset, %{ash_events_metadata: metadata})
    end
  end

  defp matcher_id(%{id: id}) when is_binary(id), do: id
  defp matcher_id(%{user_id: user_id}) when is_binary(user_id), do: user_id
  defp matcher_id(_actor), do: nil
end
