defmodule Firmowid.Ash.Timetracker.Workers.LeaveRequestEmailWorker do
  @moduledoc """
  Emails active organization admins about a newly created leave request.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.LeaveRequestEmails

  require Logger

  @doc "Enqueues admin notification email for a newly created leave request."
  @spec enqueue(Ash.UUID.t(), Ash.UUID.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(leave_request_id, organization_id) do
    %{"leave_request_id" => leave_request_id, "organization_id" => organization_id}
    |> new()
    |> Firmowid.Oban.insert(organization_id: organization_id)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    organization_id = args["organization_id"]
    leave_request_id = args["leave_request_id"]
    scope = scope(organization_id)

    Logger.info(
      "Sending leave request admin emails leave_request_id=#{leave_request_id} attempt=#{job.attempt}/#{job.max_attempts}"
    )

    case Timetracker.get_leave_request(leave_request_id,
           scope: scope,
           load: [:user, blob: [:url]],
           not_found_error?: false
         ) do
      {:ok, nil} ->
        Logger.warning("Leave request not found leave_request_id=#{leave_request_id}")
        :ok

      {:ok, leave_request} ->
        attachment = fetch_attachment(leave_request.blob)
        notify_admins(leave_request, attachment, scope)

      {:error, reason} ->
        Logger.error("Failed to load leave request leave_request_id=#{leave_request_id} reason=#{inspect(reason)}")

        {:error, reason}
    end
  end

  defp scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :leave_notifier},
      tenant: organization_id
    }
  end

  defp notify_admins(leave_request, attachment, scope) do
    admins =
      Core.list_users!(%{status: :active, role: :admin},
        query: [filter: [id: [not_eq: leave_request.user_id]]],
        scope: scope
      )

    if Enum.empty?(admins) do
      Logger.info("No admin recipients for leave request leave_request_id=#{leave_request.id}")
      :ok
    else
      LeaveRequestEmails.deliver_new_leave_request(
        admins,
        leave_request,
        attachment,
        leave_request.user
      )
    end
  end

  defp fetch_attachment(nil), do: nil

  defp fetch_attachment(%{url: url, original_filename: filename} = blob) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        Swoosh.Attachment.new({:data, body},
          filename: filename || "zalacznik",
          content_type: mime_from_blob(blob)
        )

      _ ->
        Logger.warning("Failed to download leave attachment blob_id=#{blob.id}")
        nil
    end
  end

  defp mime_from_blob(%{original_filename: filename, blob_path: blob_path}) do
    Enum.find_value([filename, blob_path], "application/octet-stream", fn path ->
      case path && MIME.from_path(path) do
        nil -> nil
        "application/octet-stream" -> nil
        mime -> mime
      end
    end)
  end
end
