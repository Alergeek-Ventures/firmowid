defmodule Firmowid.Ash.Timetracker.Validations.PendingHoursRecordChange do
  @moduledoc "Checks the persisted submission and request state before an administrator decision."
  use Ash.Resource.Validation

  import Ash.Expr

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(%{data: record}, _opts, context) do
    if record.submission_status == :submitted and not is_nil(record.change_requested_at) and
         is_nil(record.change_request_decision) and
         record.organization_id == context.actor.organization_id do
      :ok
    else
      {:error, InvalidChanges.exception(message: "The request is not awaiting a decision.")}
    end
  end

  @impl true
  def atomic(_changeset, _opts, context) do
    {:atomic, [:submission_status, :change_requested_at, :change_request_decision],
     expr(
       submission_status != :submitted or is_nil(change_requested_at) or
         not is_nil(change_request_decision) or organization_id != ^context.actor.organization_id
     ), expr(error(^InvalidChanges, %{message: "The request is not awaiting a decision."}))}
  end
end
