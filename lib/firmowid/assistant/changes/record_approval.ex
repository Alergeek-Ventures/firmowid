defmodule Firmowid.Assistant.Changes.RecordApproval do
  @moduledoc "Binds the user's decision to the unanswered calls in the validated plan."
  use Ash.Resource.Change

  alias Firmowid.Assistant

  @impl true
  def change(changeset, _opts, context) do
    decision = changeset |> Ash.Changeset.get_argument(:decision) |> Atom.to_string()

    messages =
      Assistant.list_messages!(%{conversation_id: changeset.data.id},
        actor: context.actor,
        tenant: context.tenant,
        page: false
      )

    approvals =
      changeset.data
      |> Map.put(:messages, messages)
      |> Assistant.pending_calls()
      |> Map.new(&{&1["id"], decision})

    Ash.Changeset.force_change_attribute(changeset, :approvals, approvals)
  end
end
