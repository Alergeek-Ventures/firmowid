defmodule Firmowid.Ksef.FetchDispatcher do
  @moduledoc """
  Dispatches fetch jobs for all organizations with active KSeF credentials.

  This worker is triggered by Oban cron to schedule incremental fetching
  for all organizations that have KSeF configured.
  """

  use Oban.Worker,
    queue: :ksef_fetch,
    max_attempts: 1

  import Ecto.Query

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Ksef
  alias Firmowid.Ksef.Credential
  alias Firmowid.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Get all organizations with active KSeF credentials
    organization_ids = Repo.all(from(c in Credential, select: c.organization_id), skip_organization_id: true)

    Logger.info("Dispatching KSeF fetch jobs for #{length(organization_ids)} organizations")

    # Schedule fetch job for each organization
    Enum.each(organization_ids, fn org_id ->
      Repo.put_org_id(org_id)

      last_ksef_permanent_storage_date =
        from(ci in CostInvoice, select: max(ci.ksef_permanent_storage_date))
        |> Repo.one()
        |> case do
          nil -> DateTime.shift(DateTime.utc_now(), day: -60)
          date -> DateTime.from_naive!(date, "Etc/UTC")
        end

      Ksef.fetch_cost_invoices(last_ksef_permanent_storage_date)
    end)

    :ok
  end
end
