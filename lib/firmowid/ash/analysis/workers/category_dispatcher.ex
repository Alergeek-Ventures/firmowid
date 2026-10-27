defmodule Firmowid.Ash.Analysis.Workers.CategoryDispatcher do
  @moduledoc """
  Hourly cron job, run after invoice matching, that queues classification of
  new analysis entries for each organization using the analysis, so suggestions
  are ready before the owner opens it.
  """
  use Oban.Worker, queue: :analysis_classification, max_attempts: 1

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # cross_tenant_reader: enumerate organization ids only; each check and job
    # runs under the organization's analysis_classifier actor.
    Organization
    |> Ash.Query.select([:id])
    |> Ash.read!(scope: %Scope{actor: %SystemActor{org_id: nil, role: :cross_tenant_reader}, tenant: nil})
    |> Enum.map(&Analysis.classify_new_entries_later(&1.id))
    # One organization's failure does not hold back the others' jobs.
    |> Enum.find(:ok, &match?({:error, reason} when reason != :classification_unavailable, &1))
  end
end
