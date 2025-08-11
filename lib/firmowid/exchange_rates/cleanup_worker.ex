defmodule Firmowid.ExchangeRates.CleanupWorker do
  @moduledoc false
  use Oban.Worker, queue: :default

  import Ecto.Query

  alias Firmowid.ExchangeRates.CacheEntry
  alias Firmowid.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    query = from(c in CacheEntry, where: c.expires_at < ^DateTime.utc_now())

    {deleted_count, _} = Repo.delete_all(query, skip_organization_id: true)

    {:ok, %{deleted_count: deleted_count}}
  end
end
