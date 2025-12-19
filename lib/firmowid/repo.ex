defmodule Firmowid.Repo do
  use Ecto.Repo,
    otp_app: :firmowid,
    adapter: Ecto.Adapters.Postgres,
    pool_size: 10

  require Ecto.Query

  @tenant_key {__MODULE__, :organization_id}

  def put_org_id(organization_id) do
    Process.put(@tenant_key, organization_id)
  end

  def get_org_id do
    Process.get(@tenant_key)
  end

  def drop_org_id do
    Process.delete(@tenant_key)
  end

  @impl true
  def default_options(_operation) do
    [organization_id: get_org_id()]
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

  defp skip_organization_scoping?(query, opts) do
    opts[:skip_organization_id] ||
      opts[:schema_migration] ||
      opts[:prefix] == "oban" ||
      opts[:fun_with_flags] ||
      unscoped_table?(query)
  end

  # Tables that don't have organization_id and should bypass scoping
  @unscoped_table_prefixes ~w(pg_ error_tracker_)
  @unscoped_tables ~w(requests)

  defp unscoped_table?(%Ecto.Query{from: %{source: {table, _}}}) when is_binary(table) do
    table in @unscoped_tables ||
      Enum.any?(@unscoped_table_prefixes, &String.starts_with?(table, &1))
  end

  defp unscoped_table?(_), do: false
end
