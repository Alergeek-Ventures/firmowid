defmodule Firmowid.Ash.Finances.Changes.CheckRequisitionStatus do
  @moduledoc """
  Thin dispatcher that checks GoCardless API and delegates to resource actions.

  ## Status Handling

  - "LN" (linked) → calls `:accept` action (creates bank accounts)
  - "RJ" (rejected) → calls `:reject` action (queues remote cleanup)
  - "EX" (expired) → calls `:expire` action (transitions to :expired, queues cleanup)
  - "CR/GC/UA/SA/GA" (processing) → snooze for 60 seconds (doesn't consume attempt)
  - `:expired_eua` → calls `:expire` (EUA expired on GoCardless side)
  - Unknown/error → returns error changeset (triggers Oban retry, consumes attempt)

  Token refresh on 401 is handled transparently by `ApiClient.with_token_refresh/1`.
  This change delegates all side effects to resource actions — no inline logic.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias AshOban.Errors.SnoozeJob
  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.Ash.Finances.Requisition

  require Logger

  @processing_statuses ~w(CR GC UA SA GA)

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      record = changeset.data
      tenant = record.organization_id

      case fetch_status(record.id) do
        {:ok, %{"status" => "LN"}} when record.status == :accepted ->
          Logger.debug("Requisition #{record.id} already accepted, skipping")
          changeset

        {:ok, %{"status" => "LN"}} ->
          Logger.info("Requisition #{record.id} is now linked")
          delegate_to(changeset, record, :accept, tenant)

        {:ok, %{"status" => "RJ"}} ->
          Logger.info("Requisition #{record.id} was rejected")
          delegate_to(changeset, record, :reject, tenant)

        {:ok, %{"status" => "EX"}} ->
          Logger.info("Requisition #{record.id} has expired")
          delegate_to(changeset, record, :expire, tenant)

        {:ok, %{"status" => status}} when status in @processing_statuses ->
          Logger.info("Requisition #{record.id} still processing with status: #{status}")

          Ash.Changeset.add_error(
            changeset,
            SnoozeJob.exception(snooze_for: 60)
          )

        {:ok, %{"status" => unknown}} ->
          Logger.error("Unknown requisition status: #{unknown} for #{record.id}")

          Ash.Changeset.add_error(
            changeset,
            InvalidAttribute.exception(
              field: :status,
              message: "Unknown GoCardless status: #{unknown}"
            )
          )

        {:error, :expired_eua} ->
          Logger.warning("Requisition #{record.id} EUA expired on GoCardless side")
          delegate_to(changeset, record, :expire, tenant)

        {:error, reason} ->
          Logger.error("Failed to fetch requisition status for #{record.id}: #{inspect(reason)}")

          Ash.Changeset.add_error(
            changeset,
            InvalidAttribute.exception(
              field: :status,
              message: "API error: #{inspect(reason)}"
            )
          )
      end
    end)
  end

  defp fetch_status(requisition_id) do
    ApiClient.with_token_refresh(fn ->
      ApiClient.get_requisition(requisition_id)
    end)
  end

  defp delegate_to(changeset, record, action, tenant) do
    opts = [tenant: tenant, authorize?: false, actor: %{}]

    case apply(Requisition, action, [record, opts]) do
      {:ok, _} ->
        changeset

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
