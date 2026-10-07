defmodule Firmowid.Ash.Analysis.Workers.MonthWorker do
  @moduledoc "Runs one explicitly requested monthly classification job."
  use Oban.Worker,
    queue: :analysis_classification,
    max_attempts: 3,
    unique: [
      period: :infinity,
      keys: [:organization_id, :month],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    scope = %Scope{actor: %User{id: args["user_id"]}, tenant: args["organization_id"]}

    with {:ok, user} <- User.get(args["user_id"], scope: scope),
         {:ok, month} <- Date.from_iso8601(args["month"]),
         {:ok, true} <- EntityTag.assign_month(%{month: month}, scope: %{scope | actor: user}) do
      :ok
    else
      {:error, %Ash.Error.Forbidden{} = error} -> {:cancel, error}
      {:error, reason} -> {:error, reason}
    end
  end
end
