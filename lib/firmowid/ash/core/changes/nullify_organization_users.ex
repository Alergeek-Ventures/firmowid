defmodule Firmowid.Ash.Core.Changes.NullifyOrganizationUsers do
  @moduledoc """
  Before destroying an organization, sets `organization_id` to `nil` on
  all users that belong to it via an atomic bulk update.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Core.User

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      organization_id = Ash.Changeset.get_data(changeset, :id)

      User
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> Ash.bulk_update!(:clear_organization, %{},
        strategy: :atomic,
        atomic_update: %{organization_id: nil},
        actor: context.actor
      )

      changeset
    end)
  end
end
