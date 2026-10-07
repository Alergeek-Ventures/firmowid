defmodule Firmowid.Ash.Analysis.Actions.ClassifyMonth do
  @moduledoc "Queues an explicitly requested month after checking live feature access."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Analysis.Workers.MonthWorker
  alias FirmowidWeb.Infrastructure.Flags

  @impl true
  def run(input, _opts, context) do
    key = Application.get_env(:firmowid, :typesafe_api_key)

    if context.actor.organization_id == context.tenant and is_nil(context.actor.archived_at) and
         Map.get(Flags.evaluate_for_user(context.actor), :analysis_dashboard, false) and
         is_binary(key) and byte_size(key) > 0 do
      %{
        organization_id: context.tenant,
        user_id: context.actor.id,
        month: Date.to_iso8601(Date.beginning_of_month(input.arguments.month))
      }
      |> MonthWorker.new()
      |> Oban.insert()
    else
      {:error, :classification_unavailable}
    end
  end
end
