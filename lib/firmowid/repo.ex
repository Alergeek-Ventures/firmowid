defmodule Firmowid.Repo do
  use Ecto.Repo,
    otp_app: :firmowid,
    adapter: Ecto.Adapters.Postgres,
    pool_size: 10

  use AshPostgres.Repo,
    define_ecto_repo?: false

  @impl AshPostgres.Repo
  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}

  @impl AshPostgres.Repo
  def installed_extensions, do: ["ash-functions", "uuid-ossp", "citext", "btree_gist", AshMoney.AshPostgresExtension]

  @paradedb_key {__MODULE__, :paradedb_unnamed}

  @doc """
  Enable `prepare: :unnamed` for the current process.

  ParadeDB's `@@@` operator is incompatible with Postgrex prepared statement
  caching. Call this before any Ash query that uses `paradedb_search/2`.
  The flag is process-scoped and cleared automatically on process exit.
  """
  @spec put_paradedb_unnamed :: :unnamed | nil
  def put_paradedb_unnamed do
    Process.put(@paradedb_key, :unnamed)
  end

  @doc "Disable `prepare: :unnamed` for the current process."
  @spec drop_paradedb_unnamed :: :unnamed | nil
  def drop_paradedb_unnamed do
    Process.delete(@paradedb_key)
  end

  @impl true
  def default_options(_operation) do
    case Process.get(@paradedb_key) do
      :unnamed -> [prepare: :unnamed]
      _ -> []
    end
  end

  @impl true
  def prepare_query(_operation, query, opts) do
    if opts[:oban_jobs] do
      {query, Keyword.put(opts, :prefix, "oban")}
    else
      {query, opts}
    end
  end
end
