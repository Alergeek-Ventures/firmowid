defmodule Firmowid.Ash.Billing.ResetWorker do
  @moduledoc """
  Oban worker that resets monthly invoice counters on the 1st of each month.
  """
  use Oban.Worker, queue: :default

  alias Firmowid.Ash.Billing.Limits

  @impl Oban.Worker
  def perform(_job) do
    # TODO: replace actor: %{} with a proper system actor once available
    result =
      Ash.bulk_update!(Limits, :reset_counters, %{},
        strategy: [:atomic],
        authorize?: false,
        actor: %{},
        read_action: :read_all,
        return_errors?: true
      )

    case result.errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
