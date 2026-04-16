defmodule Firmowid.Ash.Invoicing.Changes.SetOrganizationIdFromTenant do
  @moduledoc """
  Copies the current tenant into `organization_id` for tenant-scoped join resources.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.tenant do
        nil ->
          Ash.Changeset.add_error(changeset,
            field: :organization_id,
            message: "organization tenant is required"
          )

        organization_id ->
          Ash.Changeset.force_change_attribute(changeset, :organization_id, organization_id)
      end
    end)
  end
end
