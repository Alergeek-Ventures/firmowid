defmodule Firmowid.Repo do
  use Ecto.Repo,
    otp_app: :firmowid,
    adapter: Ecto.Adapters.Postgres,
    pool_size: 10

  use AshPostgres.Repo,
    define_ecto_repo?: false

  require Ecto.Query

  @impl AshPostgres.Repo
  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}

  @impl AshPostgres.Repo
  def installed_extensions, do: ["ash-functions", "uuid-ossp", "citext"]

  @paradedb_key {__MODULE__, :paradedb_unnamed}
  @skip_org_key {__MODULE__, :skip_organization_id}

  @doc """
  Skip organization scoping for the current process.

  Useful for cross-tenant Ash actions (e.g. `multitenancy :bypass`) where
  `skip_organization_id: true` cannot be passed through the Ash → Ecto opts
  chain. The flag is process-scoped and cleared automatically on process exit.
  Always pair with `drop_skip_org_id/0` in a `try/after` block.
  """
  @spec put_skip_org_id :: true | nil
  def put_skip_org_id do
    Process.put(@skip_org_key, true)
  end

  @doc "Re-enable organization scoping for the current process."
  @spec drop_skip_org_id :: true | nil
  def drop_skip_org_id do
    Process.delete(@skip_org_key)
  end

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
    opts = []
    opts = if Process.get(@skip_org_key), do: [{:skip_organization_id, true} | opts], else: opts

    case Process.get(@paradedb_key) do
      :unnamed -> [{:prepare, :unnamed} | opts]
      _ -> opts
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
