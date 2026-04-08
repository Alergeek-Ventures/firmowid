defmodule Firmowid.Ash.Invoicing.Workers.MatchingWorker do
  @moduledoc """
  Oban worker that runs invoice-to-transaction matching for all organizations
  (scheduled cron) or for a single cost invoice (on-demand after creation).
  """

  use Oban.Worker, queue: :invoicing

  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "matching"} ->
        organization_ids =
          Firmowid.Ash.Core.Organization
          |> Ash.Query.select([:id])
          |> Ash.read!(
            scope: %Scope{
              actor: %SystemActor{org_id: nil, role: :invoice_matcher},
              tenant: nil
            }
          )
          |> Enum.map(& &1.id)

        Enum.each(organization_ids, fn organization_id ->
          Logger.info("Matching invoices for organization #{organization_id}")

          ErrorTracker.set_context(%{
            organization_id: organization_id,
            job_id: job.id,
            job_name: "invoicing_matching"
          })

          ErrorTracker.add_breadcrumb(
            "Matching invoices for organization: organization_id=#{organization_id}, job_id=#{job.id}"
          )

          actor = %SystemActor{org_id: organization_id, role: :invoice_matcher}
          scope = %Scope{actor: actor, tenant: organization_id}
          match_invoices(scope)
        end)

      %{
        "name" => "match_cost_invoice",
        "cost_invoice_id" => cost_invoice_id,
        "organization_id" => organization_id
      } ->
        Logger.info("Matching cost invoice #{cost_invoice_id}")

        actor = %SystemActor{org_id: organization_id, role: :invoice_matcher}
        scope = %Scope{actor: actor, tenant: organization_id}
        InvoiceMatching.match_cost_invoice(cost_invoice_id, scope)

      _ ->
        Logger.error("Unknown job args: #{inspect(job.args)}")
    end

    :ok
  end

  defp match_invoices(scope) do
    InvoiceMatching.match_cost_invoices(scope)
    InvoiceMatching.match_sales_invoices(scope)
  end
end
