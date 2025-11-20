defmodule Firmowid.Invoicing.Worker do
  @moduledoc false
  use Oban.Worker, queue: :invoicing

  import Ecto.Query, warn: false

  alias Firmowid.Accounts.Organization
  alias Firmowid.Invoicing
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

          Sentry.Context.add_breadcrumb(%{
            category: "invoicing_matching",
            data: %{
              organization_id: organization_id,
              job: job
            }
          })

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
        Invoicing.match_cost_invoice(cost_invoice_id, organization_id)

      _ ->
        Logger.error("Unknown job args: #{inspect(job.args)}")
    end

    :ok
  end

  defp match_invoices(organization_id) do
    Invoicing.match_cost_invoices(organization_id)
    Invoicing.match_sales_invoices(organization_id)
  end
end
