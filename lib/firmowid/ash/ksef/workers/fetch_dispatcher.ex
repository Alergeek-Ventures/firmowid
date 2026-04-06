defmodule Firmowid.Ash.Ksef.Workers.FetchDispatcher do
  @moduledoc """
  Dispatches fetch jobs for all organizations with active KSeF credentials.

  This worker is triggered by Oban cron to schedule incremental fetching
  for all organizations that have KSeF configured.
  """

  use Oban.Worker,
    queue: :ksef_fetch,
    max_attempts: 1

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{}) do
    # cross_tenant_reader: reads credentials across all organizations
    actor = %SystemActor{org_id: nil, role: :cross_tenant_reader}
    scope = %Scope{actor: actor, tenant: nil}

    # Get all organizations with active KSeF credentials
    {:ok, credentials} = Credential.all_organization_ids(scope: scope)
    organization_ids = Enum.map(credentials, & &1.organization_id)

    Logger.info("Dispatching KSeF fetch jobs for #{length(organization_ids)} organizations")

    # Schedule fetch job for each organization
    Enum.each(organization_ids, fn org_id ->
      actor = %SystemActor{org_id: org_id, role: :ksef_session}
      org_scope = %Scope{actor: actor, tenant: org_id}

      last_ksef_permanent_storage_date =
        case Invoicing.last_ksef_permanent_storage_date(org_id) do
          nil -> DateTime.shift(DateTime.utc_now(), day: -60)
          date -> DateTime.from_naive!(date, "Etc/UTC")
        end

      Ksef.fetch_cost_invoices(last_ksef_permanent_storage_date, org_scope)
    end)

    :ok
  end
end
