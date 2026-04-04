defmodule Firmowid.Invoicing.Worker do
  @moduledoc false
  use Oban.Worker, queue: :invoicing

  import Ecto.Query, warn: false

  alias Firmowid.Accounts.Organization
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Repo

  require Logger

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "matching"} ->
        # Direct query for all organization IDs - this is infrastructure code
        organization_ids =
          Organization
          |> select([o], o.id)
          |> Repo.all(skip_organization_id: true)

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

          Repo.put_org_id(organization_id)
          match_invoices(organization_id)
        end)

      %{
        "name" => "match_cost_invoice",
        "cost_invoice_id" => cost_invoice_id,
        "organization_id" => organization_id
      } ->
        Logger.info("Matching cost invoice #{cost_invoice_id}")
        Repo.put_org_id(organization_id)
        InvoiceMatching.match_cost_invoice(cost_invoice_id, organization_id)

      _ ->
        Logger.error("Unknown job args: #{inspect(job.args)}")
    end

    :ok
  end

  defp match_invoices(organization_id) do
    InvoiceMatching.match_cost_invoices(organization_id)
    InvoiceMatching.match_sales_invoices(organization_id)
  end
end
