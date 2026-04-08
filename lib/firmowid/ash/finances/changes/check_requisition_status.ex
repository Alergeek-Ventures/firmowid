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
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      record = changeset.data
      tenant = record.organization_id
      ash_opts = Ash.Context.to_opts(context)

      record.id
      |> fetch_status()
      |> handle_status_result(changeset, record, tenant, ash_opts)
    end)
  end

  defp fetch_status(requisition_id) do
    ApiClient.with_token_refresh(fn ->
      ApiClient.get_requisition(requisition_id)
    end)
  end

  defp handle_status_result({:ok, %{"status" => "LN"}}, changeset, %{status: :accepted} = record, _tenant, _ash_opts) do
    Logger.debug("Requisition #{record.id} already accepted, skipping")
    changeset
  end

  defp handle_status_result({:ok, %{"status" => "LN"}}, changeset, record, tenant, ash_opts) do
    Logger.info("Requisition #{record.id} is now linked")
    delegate_to(changeset, record, :accept, tenant, ash_opts)
  end

  defp handle_status_result({:ok, %{"status" => "RJ"}}, changeset, record, tenant, ash_opts) do
    Logger.info("Requisition #{record.id} was rejected")
    delegate_to(changeset, record, :reject, tenant, ash_opts)
  end

  defp handle_status_result({:ok, %{"status" => "EX"}}, changeset, record, tenant, ash_opts) do
    Logger.info("Requisition #{record.id} has expired")
    delegate_to(changeset, record, :expire, tenant, ash_opts)
  end

  defp handle_status_result({:ok, %{"status" => status}}, changeset, record, _tenant, _ash_opts)
       when status in @processing_statuses do
    Logger.info("Requisition #{record.id} still processing with status: #{status}")

    Ash.Changeset.add_error(
      changeset,
      SnoozeJob.exception(snooze_for: 60)
    )
  end

  defp handle_status_result({:ok, %{"status" => unknown}}, changeset, record, _tenant, _ash_opts) do
    Logger.error("Unknown requisition status: #{unknown} for #{record.id}")

    Ash.Changeset.add_error(
      changeset,
      InvalidAttribute.exception(
        field: :status,
        message: "Unknown GoCardless status: #{unknown}"
      )
    )
  end

  defp handle_status_result({:error, :expired_eua}, changeset, record, tenant, ash_opts) do
    Logger.warning("Requisition #{record.id} EUA expired on GoCardless side")
    delegate_to(changeset, record, :expire, tenant, ash_opts)
  end

  defp handle_status_result({:error, :not_found}, changeset, record, tenant, ash_opts) do
    Logger.warning("Requisition #{record.id} not found on GoCardless side")
    delegate_to(changeset, record, :reject, tenant, ash_opts)
  end

  defp handle_status_result({:error, reason}, changeset, record, _tenant, _ash_opts) do
    Logger.error("Failed to fetch requisition status for #{record.id}: #{inspect(reason)}")

    Ash.Changeset.add_error(
      changeset,
      InvalidAttribute.exception(
        field: :status,
        message: "API error: #{inspect(reason)}"
      )
    )
  end

  defp delegate_to(changeset, record, action, tenant, ash_opts) do
    opts = ash_opts |> Keyword.delete(:tenant) |> Keyword.put(:tenant, tenant)

    case apply(Requisition, action, [record, opts]) do
      {:ok, _} ->
        changeset

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
