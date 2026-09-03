defmodule Firmowid.Ash.Finances.Changes.DeleteRemoteRequisition do
  @moduledoc """
  Before-action change that deletes a requisition from GoCardless.

  Used by both `:delete_remote` (scheduled update) and `:cleanup_orphan`
  (destroy). Treats `:not_found` and `:expired_eua` as success — the remote
  resource is already gone. On update actions, stamps `remote_deleted_at` so
  the scheduler stops picking up the record. On destroy actions, the timestamp
  is skipped since the record is being removed.

  Token refresh on 401 is handled transparently by `ApiClient.with_token_refresh/1`.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.ErrorKind

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      record = changeset.data

      case delete_remote(record.id) do
        {:ok, _} ->
          mark_deleted(changeset)

        {:error, reason} when reason in [:not_found, :expired_eua] ->
          Logger.info("Remote requisition #{record.id} already gone (#{reason}); treating as success")

          mark_deleted(changeset)

        {:error, reason} ->
          Logger.error("Failed to delete remote requisition",
            requisition_id: record.id,
            error_kind: ErrorKind.classify(reason)
          )

          Ash.Changeset.add_error(
            changeset,
            InvalidAttribute.exception(
              field: :id,
              message: "API error: #{inspect(reason)}"
            )
          )
      end
    end)
  end

  defp mark_deleted(%{action: %{type: :update}} = changeset) do
    Ash.Changeset.force_change_attribute(changeset, :remote_deleted_at, DateTime.utc_now())
  end

  defp mark_deleted(changeset), do: changeset

  defp delete_remote(requisition_id) do
    ApiClient.with_token_refresh(fn ->
      ApiClient.delete_requisition(requisition_id)
    end)
  end
end
