defmodule Firmowid.Invoicing.Worker do
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

          match_invoices(organization_id)
        end)

      _ ->
        Logger.error("Unknown job args: #{inspect(job.args)}")
    end

    :ok
  end

  defp match_invoices(organization_id) do
    Firmowid.Repo.put_org_id(organization_id)

    Invoicing.match_all_good_candidates_for_unconnected_cost_invoices(organization_id)
    Invoicing.match_all_good_candidates_for_unconnected_sales_invoices(organization_id)
  end
end
