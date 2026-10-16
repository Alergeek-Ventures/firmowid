defmodule Firmowid.Ash.Invoicing.Workers.MatchingWorker do
  @moduledoc """
  Oban worker that runs invoice-to-transaction matching.

  Handles two kinds of jobs:

    * `"matching"` (cron) — enqueues one `"match_organization"` job per organization,
    * `"match_organization"` — matches all pending cost and sales invoices of one
      organization.

  Matching after a new cost invoice or a bank sync runs in the listeners of
  `Firmowid.Ash.Invoicing.Signals.cost_invoice_created` and
  `Firmowid.Ash.Finances.Signals.bank_account_synced`.
  """

  use Oban.Worker, queue: :invoicing

  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind

  require Logger

  # Only one such job per organization waits in the queue at a time, so a slow
  # run does not pile up hourly cron jobs.
  defp organization_job(organization_id) do
    new(%{name: "match_organization", organization_id: organization_id},
      unique: [
        period: :infinity,
        keys: [:name, :organization_id],
        states: [:available, :scheduled, :retryable]
      ]
    )
  end

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "matching"} ->
        # cross_tenant_reader: enumerate organization ids only; matching itself
        # runs per organization under a tenant-bound invoice_matcher actor.
        organization_ids =
          Organization
          |> Ash.Query.select([:id])
          |> Ash.read!(
            scope: %Scope{
              actor: %SystemActor{org_id: nil, role: :cross_tenant_reader},
              tenant: nil
            }
          )
          |> Enum.map(& &1.id)

        Logger.info("Dispatching invoice matching for #{length(organization_ids)} organizations")

        Enum.each(organization_ids, fn organization_id ->
          organization_id
          |> organization_job()
          |> Firmowid.Oban.insert!(skip_organization_id: true)
        end)

      %{"name" => "match_organization", "organization_id" => organization_id} ->
        Logger.info("Matching invoices for organization #{organization_id}")

        scope = InvoiceMatching.matcher_scope(organization_id)
        InvoiceMatching.match_cost_invoices(scope)
        InvoiceMatching.match_sales_invoices(scope)

      _ ->
        Logger.error("Unknown matching job args",
          kind: ErrorKind.classify(job.args),
          key_count: if(is_map(job.args), do: map_size(job.args), else: 0)
        )
    end

    :ok
  end
end
