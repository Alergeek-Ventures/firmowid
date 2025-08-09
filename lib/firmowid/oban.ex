defmodule Firmowid.Oban do
  @moduledoc """
  Oban configuration for Firmowid.
  """

  alias Ecto.Changeset

  use Oban,
    otp_app: :firmowid,
    repo: Firmowid.Repo,
    prefix: "oban",
    engine: Oban.Engines.Basic,
    queues: [bank_data: 1, invoicing: 1, cost_invoices: 5, default: 1],
    plugins: [
      # retry orphaned jobs after 30 minutes
      {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
      # remove jobs after 30 days
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30},
      {Oban.Plugins.Cron,
       timezone: "Europe/Warsaw",
       crontab: [
         {"0 12 */2 * *", Firmowid.BankData.Worker,
          args: %{name: "dispatch_sync_jobs_for_all_bank_accounts"}},
         {"0 13 * * *", Firmowid.Invoicing.Worker, args: %{name: "matching"}},
         {"0 14 * * *", Firmowid.ExchangeRates.CleanupWorker, args: %{}},
         {"0 * * * *", Firmowid.BankData.CleanupWorker, args: %{}}
       ]}
    ]

  defp put_org_id(changeset, organization_id) do
    meta =
      Changeset.get_change(changeset, :meta, %{})
      |> Map.put(:organization_id, organization_id)

    Changeset.put_change(changeset, :meta, meta)
  end

  def insert(changeset, opts) do
    cond do
      opts[:skip_organization_id] ->
        Oban.insert(__MODULE__, changeset, opts)

      organization_id = Firmowid.Repo.get_org_id() ->
        changeset = put_org_id(changeset, organization_id)
        Oban.insert(__MODULE__, changeset, opts)

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end

  def insert!(changeset, opts \\ []) do
    cond do
      opts[:skip_organization_id] ->
        Oban.insert!(__MODULE__, changeset, opts)

      organization_id = Firmowid.Repo.get_org_id() ->
        changeset = put_org_id(changeset, organization_id)
        Oban.insert!(__MODULE__, changeset, opts)

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end

  @spec insert_all(list(), Keyword.t()) :: {:ok, list()} | {:error, term()}
  def insert_all(changesets, opts) do
    result =
      cond do
        opts[:skip_organization_id] ->
          Oban.insert_all(__MODULE__, changesets, opts)

        organization_id = Firmowid.Repo.get_org_id() ->
          changesets_with_org =
            changesets
            |> Enum.map(&put_org_id(&1, organization_id))

          Oban.insert_all(__MODULE__, changesets_with_org, opts)

        true ->
          raise "expected organization_id or skip_organization_id to be set"
      end

    # workaround for Oban returning a list of results in testing mode
    case result do
      result when is_list(result) -> {:ok, result}
      result -> result
    end
  end
end
