defmodule Firmowid.Invoicing.Worker do
  @moduledoc false
  use Oban.Worker, queue: :invoicing

  alias Firmowid.Accounts
  alias Firmowid.Invoicing

  require Logger

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "matching"} ->
        Accounts.list_organizations()
        |> Enum.map(& &1.id)
        |> Enum.each(fn organization_id ->
          Logger.info("Matching invoices for organization #{organization_id}")

          Sentry.Context.add_breadcrumb(%{
            category: "invoicing_matching",
            data: %{
              organization_id: organization_id,
              job: job
            }
          })

          Firmowid.Repo.put_org_id(organization_id)
          match_invoices(organization_id)
        end)

      %{
        "name" => "match_cost_invoice",
        "cost_invoice_id" => cost_invoice_id,
        "organization_id" => organization_id
      } ->
        Logger.info("Matching cost invoice #{cost_invoice_id}")
        Firmowid.Repo.put_org_id(organization_id)
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
