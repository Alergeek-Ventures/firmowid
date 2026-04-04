defmodule Firmowid.Ash.Invoicing.Changes.CalculateDueDate do
  @moduledoc """
  Ash change that calculates `due_date` from `sale_date` and `due_date_days`.

  If both `sale_date` (attribute) and `due_date_days` (argument) are present,
  sets `due_date` to `sale_date + due_date_days`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    sale_date =
      Ash.Changeset.get_attribute(changeset, :sale_date) ||
        Ash.Changeset.get_argument(changeset, :sale_date)

    due_date_days = Ash.Changeset.get_argument(changeset, :due_date_days)

    if sale_date && due_date_days do
      Ash.Changeset.force_change_attribute(
        changeset,
        :due_date,
        Date.add(sale_date, due_date_days)
      )
    else
      changeset
    end
  end
end
