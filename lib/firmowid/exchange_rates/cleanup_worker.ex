defmodule Firmowid.ExchangeRates.CleanupWorker do
  use Oban.Worker, queue: :default

  alias Firmowid.Repo
  alias Firmowid.ExchangeRates.CacheEntry
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    query = from(c in CacheEntry, where: c.expires_at < ^DateTime.utc_now())

    {deleted_count, _} =
      query
      |> Repo.delete_all(skip_organization_id: true)

    {:ok, %{deleted_count: deleted_count}}
  end
end
