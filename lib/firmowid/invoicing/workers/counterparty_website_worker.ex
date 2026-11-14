defmodule Firmowid.Invoicing.Workers.CounterpartyWebsiteWorker do
  @moduledoc """
  Looks up the websites of company counterparties (`CounterpartyWebsite`), so the
  counterparty list shows their logos: right after a company is saved or its
  details change (`EnqueueWebsiteLookup`), and daily for any lookup left undone.

  A job with `counterparty_id` looks up that counterparty, unless it was already
  looked up or is a person. A job with only `organization_id` queues one job per
  company of the organization never looked up, so a long backfill never runs as
  one job. The daily cron run (no args) queues one job per organization. A failed
  lookup is retried by Oban, then by the next daily run.
  """
  use Oban.Worker, queue: :counterparty_websites, max_attempts: 3

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Counterparty
  alias Firmowid.Invoicing.Services.CounterpartyWebsite
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Ash.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id, "counterparty_id" => counterparty_id}}) do
    scope = scope(organization_id)

    # Already looked up, now a person, or deleted: nothing to do.
    Counterparty
    |> Ash.Query.filter(id == ^counterparty_id)
    |> then(&Invoicing.list_counterparties!(%{website_unchecked: true}, scope: scope, query: &1))
    |> case do
      [counterparty] -> record(counterparty, scope)
      [] -> :ok
    end
  end

  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    %{website_unchecked: true}
    |> Invoicing.list_counterparties!(scope: scope(organization_id))
    # Behind the lookups of companies just saved, which then wait seconds, not a backfill.
    |> Enum.map(&new(%{organization_id: organization_id, counterparty_id: &1.id}, priority: 1))
    |> Firmowid.Oban.insert_all(organization_id: organization_id)

    :ok
  end

  def perform(%Oban.Job{}), do: Firmowid.Oban.insert_per_organization(__MODULE__)

  defp scope(organization_id),
    do: %Scope{actor: %SystemActor{org_id: organization_id, role: :website_finder}, tenant: organization_id}

  # An unreachable OpenAI fails the job, so Oban retries it.
  defp record(counterparty, scope) do
    case CounterpartyWebsite.find_domain(counterparty) do
      {:ok, domain} ->
        Invoicing.record_counterparty_website!(
          counterparty,
          %{website_domain: domain, website_checked_at: DateTime.utc_now()},
          scope: scope
        )

        :ok

      {:error, _error} = error ->
        error
    end
  end
end
