defmodule Firmowid.Ash.Checks.ActorBlobIdMatches do
  @moduledoc """
  Simple check: the SystemActor's blob_id matches the resource's id.

  Used to restrict invoice processors to only destroy blobs they created
  for their specific job.

  ## Usage

      authorize_if Firmowid.Ash.Checks.ActorBlobIdMatches
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Ash.SystemActor

  @impl true
  def describe(_opts) do
    "actor blob_id matches resource id"
  end

  @impl true
  def match?(%SystemActor{blob_id: nil}, _context, _opts) do
    {:ok, false}
  end

  def match?(%SystemActor{blob_id: blob_id}, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    # For destroy actions, get the record from the changeset
    record_id =
      case changeset.data do
        nil -> Ash.Changeset.get_attribute(changeset, :id)
        record -> Map.get(record, :id)
      end

    {:ok, record_id == blob_id}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
