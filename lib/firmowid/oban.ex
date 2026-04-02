defmodule Firmowid.Oban do
  @moduledoc """
  Wrapper around the default `Oban` instance that automatically injects
  `organization_id` into every job's `meta` field from the current process
  dictionary (`Firmowid.Repo.get_org_id/0`).

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

      organization_id = Firmowid.Repo.get_org_id() ->
        changeset = put_org_id(changeset, organization_id)
        Oban.insert(Oban, changeset, opts)

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end

  def insert!(changeset, opts \\ []) do
    cond do
      opts[:skip_organization_id] ->
        Oban.insert!(Oban, changeset, opts)

      organization_id = Firmowid.Repo.get_org_id() ->
        changeset = put_org_id(changeset, organization_id)
        Oban.insert!(Oban, changeset, opts)

      true ->
        raise "expected organization_id or skip_organization_id to be set"
    end
  end

  @spec insert_all(list(), Keyword.t()) :: {:ok, list()} | {:error, term()}
  def insert_all(changesets, opts \\ []) do
    result =
      cond do
        opts[:skip_organization_id] ->
          Oban.insert_all(Oban, changesets, opts)

        organization_id = Firmowid.Repo.get_org_id() ->
          changesets_with_org = Enum.map(changesets, &put_org_id(&1, organization_id))

          Oban.insert_all(Oban, changesets_with_org, opts)

        true ->
          raise "expected organization_id or skip_organization_id to be set"
      end

    # workaround for Oban returning a list of results in testing mode
    case result do
      result when is_list(result) -> {:ok, result}
      result -> result
    end
  end
end
