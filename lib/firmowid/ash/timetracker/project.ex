defmodule Firmowid.Ash.Timetracker.Project do
  @moduledoc """
  Ash resource wrapping the existing `projects` table.

  Attribute multitenancy via `organization_id`. Write actions include `create`
  (with automatic TagDefinition creation), `update` (with tag name sync),
  `archive`, `unarchive`, and `destroy` (with tag cleanup).

  Read actions: `:get` (single project by ID, loads users + counterparty) and
  `:list` (flexible listing with optional filters — archive, user membership,
  ParadeDB search, ID set).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Changes.CleanupProjectTag
  alias Firmowid.Ash.Timetracker.Changes.CreateProjectTag
  alias Firmowid.Ash.Timetracker.Changes.SyncProjectTagName
  alias Firmowid.Ash.Timetracker.ProjectUser
  alias Firmowid.Ash.Timetracker.Session

  require Ash.Query
  require Resource

  postgres do
    table "projects"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :get, get_by: [:id]
    define :list
    define :create
    define :update
    define :archive
    define :unarchive
    define :destroy
    define :set_users, args: [:user_ids]
  end

  actions do
    defaults [:read]

    # ── Read actions ──────────────────────────────────────────────────

    read :get do
      description "Get a single project by ID with users and counterparty preloaded."
      get? true

      prepare build(load: [:users, counterparty: [:display_label]])
    end

    read :list do
      description """
      Flexible project listing with optional filters.
      Duration aggregation, counterparty loading, sorting at callsite.
      """

      argument :user_id, :uuid
      argument :search, :string
      argument :active_only, :boolean
      argument :archived_only, :boolean
      argument :ids, {:array, :uuid}

      prepare build(filter: expr(exists(project_users, user_id == ^arg(:user_id)))) do
        where present(:user_id)
      end

      prepare build(filter: expr(is_nil(archived_at))) do
        where argument_equals(:active_only, true)
      end

      prepare build(filter: expr(not is_nil(archived_at))) do
        where argument_equals(:archived_only, true)
      end

      prepare build(filter: expr(id in ^arg(:ids))) do
        where present(:ids)
      end

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch, columns: ~w(name), argument: :search}
    end

    # ── Write actions ─────────────────────────────────────────────────

    create :create do
      description "Create a project with automatic TagDefinition creation for analysis tagging."

      accept [:name, :counterparty_id]
      change CreateProjectTag
    end

    update :update do
      description "Update project attributes and sync the associated tag definition name."
      accept [:name, :counterparty_id]
      require_atomic? false
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

      change set_attribute(:archived_at, nil)
    end

    update :link_tag do
      description "Internal action to link a tag definition to a project after creation."
      accept [:tag_definition_id]
    end

    destroy :destroy do
      description "Delete a project and clean up its orphaned tag definition."
      require_atomic? false
      change CleanupProjectTag
    end

    # ── User assignment ───────────────────────────────────────────────

    action :set_users, :term do
      description "Set the exact list of users for a project. Adds missing, removes extra."

      argument :project_id, :uuid, allow_nil?: false
      argument :user_ids, {:array, :uuid}, allow_nil?: false

      run fn input, context ->
        {:ok, set_project_users(input, context)}
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # System actors have no access to employee timetracking data
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # Employee: can only see assigned projects
    policy [action_type(:read), actor_attribute_equals(:role, :employee)] do
      authorize_if relates_to_actor_via([:project_users, :user])
    end

    # :invoicing and :accountant: can see all org projects
    policy [action_type(:read), {Firmowid.Ash.Checks.AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # Write and generic actions: admin only
    policy action_type(:action) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
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

    many_to_many :users, Firmowid.Ash.Core.User do
      through ProjectUser
      source_attribute_on_join_resource :project_id
      destination_attribute_on_join_resource :user_id
    end
  end

  # ── Private helpers for user assignment ──────────────────────────────

  defp set_project_users(input, context) do
    project_id = input.arguments.project_id
    user_ids = input.arguments.user_ids
    # TODO: migrate away from authorize?: false — replace with a dedicated
    # admin-scoped action on ProjectUser once project membership management
    # has its own policies (currently admin-only via :set_users policy gate).
    ash_opts = [actor: context.actor, tenant: context.tenant, authorize?: false]

    existing =
      ProjectUser
      |> Ash.Query.filter(project_id: project_id)
      |> Ash.read!(ash_opts)

    existing_user_ids = MapSet.new(existing, & &1.user_id)
    desired_user_ids = MapSet.new(user_ids)

    to_add = MapSet.difference(desired_user_ids, existing_user_ids)
    to_remove = MapSet.difference(existing_user_ids, desired_user_ids)

    # Remove users no longer in the set
    existing
    |> Enum.filter(fn pu -> MapSet.member?(to_remove, pu.user_id) end)
    |> Enum.each(fn pu -> Ash.destroy!(pu, ash_opts) end)

    # Add new users
    for uid <- to_add do
      ProjectUser
      |> Ash.Changeset.for_create(
        :create,
        %{project_id: project_id, user_id: uid},
        ash_opts
      )
      |> Ash.create!()
    end

    :ok
  end
end
