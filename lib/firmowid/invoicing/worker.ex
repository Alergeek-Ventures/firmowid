defmodule Firmowid.Invoicing.Worker do
  use Oban.Worker, queue: :invoicing

  alias Firmowid.Accounts
  alias Firmowid.Invoicing

  require Logger

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "schedule_matching"} ->
        Accounts.list_organizations()
        |> Enum.map(& &1.id)
        |> Enum.each(&schedule_matching_for_organization/1)

        :ok

      %{"name" => "match_invoices", "organization_id" => organization_id} ->
        match_invoices(organization_id)

        :ok

      _ ->
        Logger.error("Unknown job args: #{inspect(job.args)}")
        :ok
    end
  end

  defp match_invoices(organization_id) do
    Firmowid.Repo.put_org_id(organization_id)

    Invoicing.match_all_good_candidates_for_unconnected_cost_invoices(organization_id)
    Invoicing.match_all_good_candidates_for_unconnected_sales_invoices(organization_id)

    :ok
  end

  defp schedule_matching_for_organization(organization_id) do
    %{organization_id: organization_id, name: "match_invoices"}
    |> Firmowid.Invoicing.Worker.new()
    |> Oban.insert()
  end
end
