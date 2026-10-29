defmodule Firmowid.Payroll.Changes.CompleteImportedDeclaration do
  @moduledoc "Carries forward known declaration facts when an imported draft receives its dates."
  use Ash.Resource.Change

  alias Firmowid.Payroll
  alias Firmowid.Scope

  @impl true
  def change(changeset, opts, context) do
    draft? = is_nil(changeset.data.applies_from) or is_nil(changeset.data.received_on)
    applies_from = Ash.Changeset.get_attribute(changeset, :applies_from)
    received_on = Ash.Changeset.get_attribute(changeset, :received_on)

    if draft? and is_struct(applies_from, Date) and is_struct(received_on, Date) do
      previous =
        %{member_id: changeset.data.member_id, as_of: applies_from}
        |> Payroll.list_tax_declarations!(scope: Scope.new!(context.actor, changeset.tenant))
        |> List.first()

      inherit_missing(changeset, previous, Keyword.fetch!(opts, :fields))
    else
      changeset
    end
  end

  defp inherit_missing(changeset, nil, _fields), do: changeset

  defp inherit_missing(changeset, previous, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if is_nil(Map.fetch!(changeset.data, field)) and
           is_nil(Ash.Changeset.get_attribute(changeset, field)) do
        Ash.Changeset.change_attribute(changeset, field, Map.fetch!(previous, field))
      else
        changeset
      end
    end)
  end
end
