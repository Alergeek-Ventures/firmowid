defmodule Firmowid.Ash.Billing.Workers.MonthlySnapshotDispatcher do
  @moduledoc """
  Enqueues one monthly billing snapshot job per organization.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  alias Firmowid.Ash.Billing.SnapshotCalculator
  alias Firmowid.Ash.Billing.Workers.OrganizationSnapshotWorker
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Oban, as: FirmowidOban

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{}) do
    month = SnapshotCalculator.previous_month(DateTime.now!("Europe/Warsaw"))

    organization_ids =
      Organization
      |> Ash.Query.select([:id])
      |> Ash.read!(scope: %Scope{actor: %SystemActor{org_id: nil, role: :cross_tenant_reader}, tenant: nil})
      |> Enum.map(& &1.id)

    Logger.info("Dispatching billing snapshot jobs for #{length(organization_ids)} organizations and month #{month}")

    Enum.each(organization_ids, fn organization_id ->
      %{organization_id: organization_id, month: Date.to_iso8601(month)}
      |> OrganizationSnapshotWorker.new()
      |> FirmowidOban.insert!(organization_id: organization_id)
    end)

    :ok
  end
end
