defmodule Firmowid.Ksef.Workers.FetchDispatcher do
  @moduledoc """
  Dispatches fetch jobs for all organizations with active KSeF credentials.

  This worker is triggered by Oban cron to schedule incremental fetching
  for all organizations that have KSeF configured.
  """

  use Oban.Worker,
    queue: :ksef_fetch,
    max_attempts: 1

  alias Firmowid.Ksef
  alias Firmowid.Ksef.Credential
  alias Firmowid.Scope
  alias Firmowid.SystemActor

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

      Ksef.fetch_new_invoices(org_scope)
    end)

    :ok
  end
end
