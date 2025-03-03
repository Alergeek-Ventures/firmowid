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

  def get_org_id() do
    Process.get(@tenant_key)
  end

  def drop_org_id() do
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

      organization_id = opts[:organization_id] ->
        {Ecto.Query.where(query, organization_id: ^organization_id), opts}

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end
end
