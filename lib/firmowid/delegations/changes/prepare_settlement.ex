defmodule Firmowid.Delegations.Changes.PrepareSettlement do
  @moduledoc "Allocates settlement metadata after the settlement passes final validation."

  use Ash.Resource.Change

  alias Ecto.Adapters.SQL
  alias Firmowid.Repo

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &prepare/1)
  end

  defp prepare(changeset) do
    changeset
    |> maybe_allocate_number()
    |> Ash.Changeset.force_change_attribute(
      :settlement_prepared_at,
      DateTime.truncate(DateTime.utc_now(), :second)
    )
  end

  # A reopened settlement keeps its number, including the year it was first allocated in.
  defp maybe_allocate_number(changeset) do
    case Ash.Changeset.get_attribute(changeset, :settlement_sequence) do
      nil -> allocate_number(changeset)
      _existing -> changeset
    end
  end

  defp allocate_number(changeset) do
    organization_id = changeset.data.organization_id
    year = Date.utc_today().year

    with {:ok, _result} <- lock_numbering(organization_id, year),
         {:ok, sequence} <- next_sequence(organization_id, year) do
      changeset
      |> Ash.Changeset.force_change_attribute(:settlement_sequence, sequence)
      |> Ash.Changeset.force_change_attribute(:settlement_year, year)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp lock_numbering(organization_id, year) do
    SQL.query(
      Repo,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, $2))",
      [organization_id, year]
    )
  end

  defp next_sequence(organization_id, year) do
    case SQL.query(
           Repo,
           "SELECT COALESCE(MAX(settlement_sequence), 0) + 1 FROM delegations WHERE organization_id = $1 AND settlement_year = $2",
           [Ecto.UUID.dump!(organization_id), year]
         ) do
      {:ok, %{rows: [[sequence]]}} -> {:ok, sequence}
      {:error, error} -> {:error, error}
    end
  end
end
