defmodule Firmowid.Oban do
  @moduledoc """
  Oban configuration for Firmowid.
  """

  use Oban,
    otp_app: :firmowid,
    repo: Firmowid.Repo,
    prefix: "oban",
    engine: Oban.Engines.Basic,
    queues: [
      bank_data: 1,
      invoicing: 1,
      cost_invoices: 5,
      inbound_emails: 3,
      ksef_submissions: 2,
      ksef_sessions: 5,
      ksef_fetch: 2,
      default: 1
    ],
    plugins: [
      {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 30)},
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 30},
      # retry orphaned jobs after 30 minutes
      {
        Oban.Plugins.Cron,
        # remove jobs after 30 days
        timezone: "Europe/Warsaw",
        crontab: [
          {"0 12 */2 * *", Firmowid.BankData.Worker, args: %{name: "dispatch_sync_jobs_for_all_bank_accounts"}},
          {"0 13 * * *", Firmowid.BankData.CleanupWorker, args: %{}},
          {"0 13 * * *", Firmowid.Invoicing.Worker, args: %{name: "matching"}},
          {"0 14 * * *", Firmowid.Currencies.CleanupWorker, args: %{}},
          {"0 */2 * * *", Firmowid.Ksef.FetchDispatcher, args: %{}}
        ]
      }
    ]

  alias Ecto.Changeset

  defp put_org_id(changeset, organization_id) do
    meta =
      changeset
      |> Changeset.get_change(:meta, %{})
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
          changesets_with_org = Enum.map(changesets, &put_org_id(&1, organization_id))

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
