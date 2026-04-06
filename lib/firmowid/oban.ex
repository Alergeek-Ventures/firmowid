defmodule Firmowid.Oban do
  @moduledoc """
  Wrapper around the default `Oban` instance that injects `organization_id`
  into every job's `meta` field.

  Pass `organization_id: org_id` to inject an explicit org_id into job meta.
  Pass `skip_organization_id: true` when the org_id is embedded in the job
  args directly (e.g. KSeF workers) and no meta injection is needed.

  All non-Ash workers should insert jobs through this module to ensure
  multi-tenant scoping. AshOban-managed workers use Ash's own tenant
  mechanism (`args["tenant"]`) and insert directly via `Oban.insert!/1`.
  """

  alias Ecto.Changeset

  @doc "Cancels all jobs matching the given queryable. Delegates to `Oban.cancel_all_jobs/2`."
  @spec cancel_all_jobs(Ecto.Queryable.t()) :: {:ok, non_neg_integer()}
  def cancel_all_jobs(queryable) do
    Oban.cancel_all_jobs(Oban, queryable)
  end

  defp put_org_id(changeset, organization_id) do
    meta =
      changeset
      |> Changeset.get_change(:meta, %{})
      |> Map.put(:organization_id, organization_id)

    Changeset.put_change(changeset, :meta, meta)
  end

  def insert(changeset, opts \\ []) do
    cond do
      opts[:skip_organization_id] ->
        Oban.insert(Oban, changeset, opts)

      organization_id = opts[:organization_id] ->
        changeset = put_org_id(changeset, organization_id)
        Oban.insert(Oban, changeset, opts)

      true ->
        raise "expected organization_id: org_id option or skip_organization_id: true to be set"
    end
  end

  def insert!(changeset, opts \\ []) do
    cond do
      opts[:skip_organization_id] ->
        Oban.insert!(Oban, changeset, opts)

      organization_id = opts[:organization_id] ->
        changeset = put_org_id(changeset, organization_id)
        Oban.insert!(Oban, changeset, opts)

      true ->
        raise "expected organization_id: org_id option or skip_organization_id: true to be set"
    end
  end

  @spec insert_all(list(), Keyword.t()) :: {:ok, list()} | {:error, term()}
  def insert_all(changesets, opts \\ []) do
    result =
      cond do
        opts[:skip_organization_id] ->
          Oban.insert_all(Oban, changesets, opts)

        organization_id = opts[:organization_id] ->
          changesets_with_org = Enum.map(changesets, &put_org_id(&1, organization_id))

          Oban.insert_all(Oban, changesets_with_org, opts)

        true ->
          raise "expected organization_id: org_id option or skip_organization_id: true to be set"
      end

    # workaround for Oban returning a list of results in testing mode
    case result do
      result when is_list(result) -> {:ok, result}
      result -> result
    end
  end
end
