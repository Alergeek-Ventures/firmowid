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
      opts[:skip_organization_id] || opts[:schema_migration] || opts[:prefix] == "oban" ->
        {query, opts}

      # ErrorTracker queries PostgreSQL system tables during migrations
      pg_system_table_query?(query) ->
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

  # Check if query is against PostgreSQL system tables (used by ErrorTracker migrations)
  defp pg_system_table_query?(%Ecto.Query{} = query) do
    case query.from do
      %{source: {source, _}} when is_binary(source) ->
        String.starts_with?(source, "pg_") or String.starts_with?(source, "error_tracker_")

      _ ->
        false
    end
  end

  defp pg_system_table_query?(_), do: false
end
