defmodule Firmowid.Ash.Core.Changes.SetOwnerOrganization do
  @moduledoc """
  After creating an organization, updates the owner user to belong to
  the new organization and promotes them to `:admin` role.
  """
  # TODO: extract bridge_opts tenant-extraction pattern into a shared helper
  # (duplicated in OrganizationInvite and other changes)
  use Ash.Resource.Change

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.SystemActor

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      actor = %SystemActor{
        org_id: organization.id,
        role: :organization_owner_setup,
        user_id: organization.owner_id
      }

      bridge_opts =
        case Map.get(context, :tenant) do
          nil -> [actor: actor]
          tenant -> [actor: actor, tenant: tenant]
        end

      owner = Ash.get!(User, organization.owner_id, bridge_opts)

      owner =
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
