defmodule Firmowid.Repo do
  use Ecto.Repo,
    otp_app: :firmowid,
    adapter: Ecto.Adapters.Postgres,
    pool_size: 10

  use AshPostgres.Repo,
    define_ecto_repo?: false,
    warn_on_missing_ash_functions?: false

  require Ecto.Query

  @impl AshPostgres.Repo
  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}

  @impl AshPostgres.Repo
  def installed_extensions, do: ["uuid-ossp"]

  @tenant_key {__MODULE__, :organization_id}
  @paradedb_key {__MODULE__, :paradedb_unnamed}
  @skip_org_key {__MODULE__, :skip_organization_id}

  def put_org_id(organization_id) do
    Process.put(@tenant_key, organization_id)
  end

  def get_org_id do
    Process.get(@tenant_key)
  end

  def drop_org_id do
    Process.delete(@tenant_key)
  end

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
    opts = [organization_id: get_org_id()]

    opts =
      if Process.get(@skip_org_key),
        do: [{:skip_organization_id, true} | opts],
        else: opts

    case Process.get(@paradedb_key) do
      :unnamed -> [{:prepare, :unnamed} | opts]
      _ -> opts
    end
  end

  @impl true
  def prepare_query(_operation, query, opts) do
    cond do
      skip_organization_scoping?(query, opts) ->
        {query, opts}

      organization_id = opts[:organization_id] ->
        if opts[:oban_jobs] do
          opts = Keyword.put(opts, :prefix, "oban")
          {Ecto.Query.where(query, [j], j.meta["organization_id"] == ^organization_id), opts}
        else
          {Ecto.Query.where(query, organization_id: ^organization_id), opts}
        end

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end

  # Organization scoping is skipped for:
  # - Explicit opt-out via `skip_organization_id: true`

  # - Schema migrations (Ecto internal)
  # - Oban queries (uses "oban" prefix)
  # - FunWithFlags queries (passes `fun_with_flags: true`)

  # - Unscoped tables (see @unscoped_tables and @unscoped_table_prefixes)
  # - Ash-managed tables (Ash multitenancy handles the WHERE clause)

  # Tables managed by Ash resources with `multitenancy strategy: :attribute`.
  # Ash enforces the organization_id WHERE clause via `set_tenant/1` —
  # prepare_query stands down to avoid double-filtering or crashes in
  # background jobs (AshOban) where the process dictionary isn't set.
  @ash_managed_tables ~w(requisitions)

  defp skip_organization_scoping?(query, opts) do
    opts[:skip_organization_id] ||
      opts[:schema_migration] ||
      opts[:prefix] == "oban" ||
      opts[:fun_with_flags] ||
      unscoped_table?(query) ||
      ash_managed_table?(query)
  end

  # Tables that don't have organization_id and should bypass scoping
  @unscoped_table_prefixes ~w(pg_ error_tracker_)
  @unscoped_tables ~w(exchange_rates_cache ksef_credentials organizations requests)

  defp unscoped_table?(%Ecto.Query{from: %{source: {table, _}}}) when is_binary(table) do
    table in @unscoped_tables ||
      Enum.any?(@unscoped_table_prefixes, &String.starts_with?(table, &1))
  end

  defp unscoped_table?(_), do: false

  defp ash_managed_table?(%Ecto.Query{from: %{source: {table, _}}}) when is_binary(table),
    do: table in @ash_managed_tables

  defp ash_managed_table?(_), do: false
end
