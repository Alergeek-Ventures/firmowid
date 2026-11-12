defmodule Firmowid.Delegations.Validations.ExpenseDetailsMatchKind do
  @moduledoc "Ensures an expense category and its typed details agree."

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  # The details union names its member types after the expense categories.
  @impl true
  def validate(changeset, _opts, _context) do
    case {Ash.Changeset.get_attribute(changeset, :kind), Ash.Changeset.get_attribute(changeset, :details)} do
      {kind, %Ash.Union{type: kind}} ->
        :ok

      _mismatch ->
        {:error, field: :details, message: gettext_noop("do not match the expense category")}
    end
  end
end
