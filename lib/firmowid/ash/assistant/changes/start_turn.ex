defmodule Firmowid.Ash.Assistant.Changes.StartTurn do
  @moduledoc "Validates the rendered revision and atomically enqueues its new assistant run."
  use Ash.Resource.Change

  alias Firmowid.Ash.Assistant

  @impl true
  def change(changeset, opts, _context) do
    conversation = changeset.data
    expected = Ash.Changeset.get_argument(changeset, :expected_version)

    cond do
      expected != conversation.version ->
        Ash.Changeset.add_error(changeset,
          field: :expected_version,
          message: "stale_conversation"
        )

      opts[:mode] == :message and conversation.status not in [:idle, :failed] ->
        Ash.Changeset.add_error(changeset, field: :text, message: "conversation_busy")

      opts[:mode] == :approval and conversation.status != :awaiting_approval ->
        Ash.Changeset.add_error(changeset, field: :decision, message: "no_pending_plan")

      true ->
        changeset
        |> prepare_turn(opts[:mode])
        |> Ash.Changeset.force_change_attribute(:status, :running)
        |> Ash.Changeset.force_change_attribute(:error, nil)
        |> Ash.Changeset.force_change_attribute(:run_id, Ash.UUID.generate())
        |> Ash.Changeset.after_action(fn _changeset, record ->
          # after_action is still inside the short resource transaction: row and
          # job commit together, with a unique run id preventing stale jobs.
          AshOban.run_trigger(record, :respond,
            tenant: record.organization_id,
            action_arguments: %{run_id: record.run_id}
          )

          {:ok, record}
        end)
    end
  end

  defp prepare_turn(changeset, :message) do
    text = Ash.Changeset.get_argument(changeset, :text)

    transcript =
      changeset.data.transcript ++
        [%{"role" => "user", "text" => text}, %{"role" => "assistant", "parts" => []}]

    changeset
    |> Ash.Changeset.force_change_attribute(:transcript, transcript)
    |> Ash.Changeset.force_change_attribute(:approvals, %{})
  end

  defp prepare_turn(changeset, :approval) do
    decision = changeset |> Ash.Changeset.get_argument(:decision) |> Atom.to_string()
    approvals = Map.new(Assistant.pending_calls(changeset.data), &{&1["id"], decision})
    Ash.Changeset.force_change_attribute(changeset, :approvals, approvals)
  end
end
