defmodule Firmowid.Ash.Timetracker.Project do
  @moduledoc """
  Ash resource wrapping the existing `projects` table.

  Attribute multitenancy via `organization_id`. Write actions include `create`
  (with automatic TagDefinition creation), `update` (with tag name sync),
  `archive`, `unarchive`, and `destroy` (with tag cleanup).

  Read actions: `:get` (single project by ID, loads users + counterparty) and
  `:list` (flexible listing with optional filters — archive, activity period,
  user membership, ParadeDB search, ID set, tag definition).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Changes.CleanupProjectTag
  alias Firmowid.Ash.Timetracker.Changes.CreateProjectTag
  alias Firmowid.Ash.Timetracker.Changes.SyncProjectTagName
  alias Firmowid.Ash.Timetracker.ProjectUser
  alias Firmowid.Ash.Timetracker.Session

  require Resource

  postgres do
    table "projects"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :get, get_by: [:id]
    define :list
    define :create
    define :update
    define :archive
    define :unarchive
    define :destroy
    define :link_tag, action: :link_tag
  end

  actions do
    defaults [:read]

    read :get do
      description "Get a single project by ID with members and counterparty preloaded."
      get? true

      prepare build(load: [members: :user, counterparty: [:display_label]])
    end

    read :list do
      description """
      Flexible project listing with optional filters.
      Duration aggregation, counterparty loading, sorting at callsite.
      """

      argument :member_id, :uuid
      argument :tag_definition_id, :uuid
      argument :search, :string

      argument :status, :atom do
        constraints one_of: [:active, :archived]
      end

      argument :ids, {:array, :uuid}

      argument :active_from, :date do
        description "Only projects not archived before this date."
      end

      argument :active_to, :date do
        description "Only projects created or with logged work on or before this date."
      end

      prepare build(filter: expr(exists(project_users, member_id == ^arg(:member_id)))) do
        where present(:member_id)
      end

      prepare build(filter: expr(tag_definition_id == ^arg(:tag_definition_id))) do
        where present(:tag_definition_id)
      end

      prepare build(filter: expr(is_nil(archived_at))) do
        where argument_equals(:status, :active)
      end

      prepare build(filter: expr(not is_nil(archived_at))) do
        where argument_equals(:status, :archived)
      end

      prepare build(filter: expr(id in ^arg(:ids))) do
        where present(:ids)
      end

      prepare build(filter: expr(is_nil(archived_at) or archived_at >= ^arg(:active_from))) do
        where present(:active_from)
      end

      prepare build(
                filter:
                  expr(
                    type(inserted_at, :date) <= ^arg(:active_to) or
                      type(first_session_at, :date) <= ^arg(:active_to)
                  )
              ) do
        where present(:active_to)
      end

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch, columns: ~w(name)a, argument: :search}
    end

    read :list_current_user do
      description "List projects assigned to the authenticated user."

      argument :status, :atom do
        description "Filter by status: active or archived. Omit to list all projects."
        constraints one_of: [:active, :archived]
      end

      prepare build(filter: expr(exists(project_users, member_id == ^actor([:member, :id]))))

      prepare build(filter: expr(is_nil(archived_at))) do
        where argument_equals(:status, :active)
      end

      prepare build(filter: expr(not is_nil(archived_at))) do
        where argument_equals(:status, :archived)
      end
    end

    create :create do
      description "Create a project with automatic TagDefinition creation for analysis tagging."

      accept [:name, :counterparty_id]
      argument :member_ids, {:array, :uuid}, allow_nil?: true

      change manage_relationship(:member_ids, :members, type: :append_and_remove)
      change CreateProjectTag
    end

    update :update do
      description "Update project attributes and sync the associated tag definition name."
      primary? true
      accept [:name, :counterparty_id]
      argument :member_ids, {:array, :uuid}, allow_nil?: true
      require_atomic? false

      change manage_relationship(:member_ids, :members, type: :append_and_remove)
      change SyncProjectTagName, where: [changing(:name)]
    end

    update :archive do
      description "Archive a project by setting archived_at to today."
      accept []
      require_atomic? false

      change set_attribute(:archived_at, &Date.utc_today/0)
    end

    update :unarchive do
      description "Unarchive a project by clearing archived_at."
      accept []
      require_atomic? false

      change set_attribute(:archived_at, nil)
    end

    update :link_tag do
      description "Internal action to link a tag definition to a project after creation."
      accept [:tag_definition_id]
      require_atomic? false
    end

    destroy :destroy do
      description "Delete a project and clean up its orphaned tag definition."
      primary? true
      require_atomic? false
      change CleanupProjectTag
    end
  end

  policies do
    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:list, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    bypass [
      {SystemActorRole, roles: [:project_tag_manager]},
      action([:list, :link_tag])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    # System actors have no access to employee timetracking data
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if {Firmowid.Ash.Checks.AtLeastRole, role: :invoicing}
      authorize_if expr(exists(project_users, member_id == ^actor([:member, :id])))
      authorize_if accessing_from(Session, :project)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      public? true
      allow_nil? false
      constraints min_length: 2, max_length: 100
    end

    attribute :archived_at, :date, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :counterparty, Firmowid.Ash.Invoicing.Counterparty do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :tag_definition, Firmowid.Ash.Analysis.TagDefinition do
      allow_nil? true
      attribute_writable? true
    end

    has_many :sessions, Session
    has_many :project_users, ProjectUser

    many_to_many :members, Firmowid.Ash.Core.Member do
      through ProjectUser
      source_attribute_on_join_resource :project_id
      destination_attribute_on_join_resource :member_id
    end
  end

  aggregates do
    min :first_session_at, :sessions, :start_datetime do
      description "Start of the earliest logged session; work may predate the project record."
      # Only the date leaves the aggregate, so employees' sessions stay private.
      authorize? false
    end
  end

  identities do
    identity :unique_name_per_org, [:name, :organization_id],
      pre_check?: true,
      message: "has already been taken"
  end
end
