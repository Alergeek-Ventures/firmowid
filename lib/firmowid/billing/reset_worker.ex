defmodule Firmowid.Billing.ResetWorker do
  @moduledoc """
  Oban worker that resets monthly invoice counters on the 1st of each month.
  """
  use Oban.Worker, queue: :default

  alias Firmowid.Billing

  @impl Oban.Worker
  def perform(_job) do
    {count, _} = Billing.reset_monthly_counters()
    {:ok, %{reset_count: count}}
  end
end
