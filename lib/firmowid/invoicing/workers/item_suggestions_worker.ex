defmodule Firmowid.Invoicing.Workers.ItemSuggestionsWorker do
  @moduledoc """
  Keeps every organization's item name suggestions (`Firmowid.Invoicing.ItemSuggestions`)
  at most a month old.

  The daily cron run (no args) queues one job per organization. A job with
  `organization_id` generates the suggestions of an organization that has none
  yet or whose suggestions are a month old, so a new organization gets them the
  next night and the others once a month. A failed generation is retried by
  Oban, then by the next daily run.
  """
  use Oban.Worker, queue: :item_suggestions, max_attempts: 3

  alias Firmowid.Invoicing
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :item_suggester},
      tenant: organization_id
    }

    if fresh?(Invoicing.get_item_suggestions!(scope: scope)) do
      :ok
    else
      Invoicing.generate_item_suggestions!(%{}, scope: scope)
      :ok
    end
  end

  def perform(%Oban.Job{}), do: Firmowid.Oban.insert_per_organization(__MODULE__)

  defp fresh?(nil), do: false

  defp fresh?(%{updated_at: updated_at}), do: DateTime.after?(updated_at, DateTime.shift(DateTime.utc_now(), month: -1))
end
