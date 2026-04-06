defmodule Firmowid.Ash.Core.Changes.SetOwnerOrganization do
  @moduledoc """
  After creating an organization, updates the owner user to belong to
  the new organization and promotes them to `:admin` role.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Core.User

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      bridge_opts = [authorize?: false, actor: %{}]

      owner = Ash.get!(User, organization.owner_id, bridge_opts)

      owner
      |> Ash.Changeset.for_update(
        :set_organization,
        %{organization_id: organization.id},
        bridge_opts
      )
      |> Ash.update!()

      owner
      |> Ash.Changeset.for_update(:update_role, %{role: :admin}, bridge_opts)
      |> Ash.update!()

      {:ok, organization}
    end)
  end
end
