defmodule Firmowid.Ash.Timetracker.Changes.EnqueueLeaveRequestEmail do
  @moduledoc """
  Enqueues an Oban job to email org admins after a leave request is created.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Timetracker.Workers.LeaveRequestEmailWorker

  require Logger

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, leave_request ->
      args = %{
        "organization_id" => leave_request.organization_id,
        "leave_request_id" => leave_request.id
      }

      case args
           |> LeaveRequestEmailWorker.new()
           |> Firmowid.Oban.insert(organization_id: leave_request.organization_id) do
        {:ok, _job} ->
          Logger.info(
            "Enqueued leave request admin email leave_request_id=#{leave_request.id} org=#{leave_request.organization_id}"
          )

          {:ok, leave_request}

        {:error, reason} ->
          Logger.error(
            "Failed to enqueue leave request admin email leave_request_id=#{leave_request.id} reason=#{inspect(reason)}"
          )

          {:ok, leave_request}
      end
    end)
  end
end
