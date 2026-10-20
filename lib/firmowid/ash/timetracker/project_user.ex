defmodule Firmowid.Ash.Timetracker.ProjectUser do
  @moduledoc """
  Ash resource wrapping the existing `projects_users` join table: an organization
  member assigned to a project.

  Attribute multitenancy via `organization_id`. Managed as a relationship
  on `Project` — typically not interacted with directly.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "projects_users"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
    define :create
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Assign an organization member to a project."
      primary? true
      accept [:project_id, :member_id]
    end
  end

  policies do
    policy [action_type(:read), {ActorRole, role: :employee}] do
      authorize_if expr(member_id == ^actor([:member, :id]))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :project, Firmowid.Ash.Timetracker.Project do
      public? true
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :member, Firmowid.Ash.Core.Member do
      public? true
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_project_member, [:project_id, :member_id]
  end
end
