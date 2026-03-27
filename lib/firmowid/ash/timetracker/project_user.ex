defmodule Firmowid.Ash.Timetracker.ProjectUser do
  @moduledoc """
  Ash resource wrapping the existing `projects_users` join table.

  Attribute multitenancy via `organization_id`. Managed as a relationship
  on `Project` — typically not interacted with directly.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  code_interface do
    define(:create)
    define(:destroy)
  end

  postgres do
    table("projects_users")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :project, Firmowid.Ash.Timetracker.Project do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(false)
    end
  end

  identities do
    identity(:unique_project_user, [:project_id, :user_id])
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(always())
    end
  end
end
