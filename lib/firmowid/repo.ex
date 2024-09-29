defmodule Firmowid.Repo do
  use Ecto.Repo,
    otp_app: :firmowid,
    adapter: Ecto.Adapters.Postgres,
    pool_size: 10

  require Ecto.Query

  @impl true
  def prepare_query(_operation, query, opts) do
    cond do
      opts[:skip_organization_id] || opts[:schema_migration] ->
        {query, opts}

      organization_id = opts[:organization_id] ->
        {Ecto.Query.where(query, organization_id: ^organization_id), opts}

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end
end
