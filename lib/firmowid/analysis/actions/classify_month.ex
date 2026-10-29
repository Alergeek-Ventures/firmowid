defmodule Firmowid.Analysis.Actions.ClassifyMonth do
  @moduledoc "Queues an explicitly requested month when the classifier is configured."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Analysis.Workers.MonthWorker

  @impl true
  def run(input, _opts, context) do
    key = Application.get_env(:firmowid, :typesafe_api_key)

    if context.actor.member.organization_id == context.tenant and
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
