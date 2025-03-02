defmodule Firmowid.Invoicing.Worker do
  use Oban.Worker, queue: :invoicing

  alias Firmowid.Accounts
  alias Firmowid.Invoicing

  require Logger

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "schedule_matching"} ->
        schedule_matching()

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
    try do
      Firmowid.Repo.put_org_id(organization_id)
      Invoicing.match_all_good_candidates_for_unconnected_cost_invoices(organization_id)
      Invoicing.match_all_good_candidates_for_unconnected_sales_invoices(organization_id)
    rescue
      error ->
        Sentry.capture_exception(error)

        Logger.error(
          "Failed to match invoices for organization #{organization_id} #{inspect(error)}"
        )
    end

    :ok
  end

  defp schedule_matching_for_organization(organization_id) do
    today = Date.utc_today()
    eleven_pm = ~T[23:00:00]

    {:ok, scheduled_at} = NaiveDateTime.new(today, eleven_pm)

    %{organization_id: organization_id, name: "match_invoices"}
    |> Firmowid.Invoicing.Worker.new(
      scheduled_at: scheduled_at,
      unique: [
        timestamp: :scheduled_at
      ]
    )
    |> Oban.insert()
  end

  defp schedule_matching() do
    Accounts.list_organizations()
    |> Enum.map(& &1.id)
    |> Enum.each(&schedule_matching_for_organization/1)
  end
end
