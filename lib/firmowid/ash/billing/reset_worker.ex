defmodule Firmowid.Ash.Billing.ResetWorker do
  @moduledoc """
  Oban worker that resets monthly invoice counters on the 1st of each month.
  """
  use Oban.Worker, queue: :default

  alias Firmowid.Ash.Billing.Limits

  @impl Oban.Worker
  def perform(_job) do
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    Limits.reset_monthly_counters(authorize?: false, actor: %{})
  end
end
