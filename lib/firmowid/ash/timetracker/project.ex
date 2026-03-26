defmodule Firmowid.Ash.Timetracker.Project do
  @moduledoc """
  Ash resource wrapping the existing `projects` table.

  Read-only for now — writes still go through `Firmowid.Timetracker` context.
  Attribute multitenancy via `organization_id`.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.ProjectUser

  require Resource

  postgres do
    table("projects")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute(:name, :string, public?: true)
    attribute(:archived_at, :date, public?: true)

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(false)
    end

    belongs_to :counterparty, Firmowid.Ash.Core.Counterparty do
      allow_nil?(true)
      attribute_writable?(true)
    end

    belongs_to :tag_definition, Firmowid.Ash.Core.TagDefinition do
      allow_nil?(true)
      attribute_writable?(true)
    end

    has_many :sessions, Firmowid.Ash.Timetracker.Session
    has_many :project_users, ProjectUser

    many_to_many :users, Firmowid.Ash.Core.User do
      through(ProjectUser)
      source_attribute_on_join_resource(:project_id)
      destination_attribute_on_join_resource(:user_id)
    end
  end

  actions do
    defaults([:read])
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
