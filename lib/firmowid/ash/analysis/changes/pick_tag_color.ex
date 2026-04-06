defmodule Firmowid.Ash.Analysis.Changes.PickTagColor do
  @moduledoc """
  Assigns a color from a rotating palette based on the count of existing
  tag definitions in the organization. Used by the `:create_for_project`
  action on `TagDefinition`.
  """
  use Ash.Resource.Change

  @palette ~w(#2563EB #059669 #D97706 #7C3AED #DB2777 #0891B2 #4F46E5 #DC2626 #65A30D #0D9488)

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, context) do
    scope = %Firmowid.Ash.Scope{
      actor: context.actor,
      tenant: context.tenant
    }

    count =
      Firmowid.Ash.Analysis.TagDefinition
      |> Ash.Query.for_read(:read, %{}, scope: scope)
      |> Ash.count!(scope: scope)

    color = Enum.at(@palette, rem(count, length(@palette)))
    Ash.Changeset.force_change_attribute(changeset, :color, color)
  end
end
