defmodule Firmowid.Ash.Billing.Workers.OrganizationSnapshotWorker do
  @moduledoc """
  Creates a factual monthly billing snapshot for one organization when missing.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Firmowid.Ash.Billing
  alias Firmowid.Ash.Billing.SnapshotCalculator

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{args: %{"organization_id" => organization_id, "month" => month_iso8601}}) do
    month = Date.from_iso8601!(month_iso8601)
    scope = SnapshotCalculator.org_scope(organization_id)

    case SnapshotCalculator.existing_snapshot(organization_id, month) do
      nil ->
        create_snapshot(scope, organization_id, month)

      _snapshot ->
        Logger.info("Billing snapshot already exists for organization #{organization_id} and month #{month}")

        :ok
    end
  end

  defp create_snapshot(scope, organization_id, month) do
    attrs = SnapshotCalculator.build_snapshot_attrs!(organization_id, month)

    case Billing.create_billing_snapshot(attrs, scope: scope) do
      {:ok, _snapshot} ->
        Logger.info("Created billing snapshot for organization #{organization_id} and month #{month}")

        :ok

      {:error, error} ->
        if SnapshotCalculator.existing_snapshot(organization_id, month) do
          Logger.info(
            "Billing snapshot already created concurrently for organization #{organization_id} and month #{month}"
          )

          :ok
        else
          {:error, Exception.message(error)}
        end
    end
  end
end
