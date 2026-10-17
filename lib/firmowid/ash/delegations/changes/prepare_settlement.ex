defmodule Firmowid.Ash.Delegations.Changes.PrepareSettlement do
  @moduledoc "Allocates settlement metadata after the settlement passes final validation."

  use Ash.Resource.Change

  alias Ecto.Adapters.SQL
  alias Firmowid.Repo

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &prepare/1)
  end

  defp prepare(changeset) do
    year = Date.utc_today().year

    with {:ok, _result} <- lock_numbering(changeset.data.organization_id, year),
         {:ok, sequence} <- next_sequence(changeset.data.organization_id, year) do
      changeset
      |> maybe_set_sequence(sequence)
      |> Ash.Changeset.force_change_attribute(:settlement_year, year)
      |> Ash.Changeset.force_change_attribute(
        :settlement_prepared_at,
        DateTime.truncate(DateTime.utc_now(), :second)
      )
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp maybe_set_sequence(changeset, sequence) do
    case Ash.Changeset.get_attribute(changeset, :settlement_sequence) do
      nil -> Ash.Changeset.force_change_attribute(changeset, :settlement_sequence, sequence)
      _existing -> changeset
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
