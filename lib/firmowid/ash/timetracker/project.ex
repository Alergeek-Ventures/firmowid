defmodule Firmowid.Ash.Timetracker.Project do
  @moduledoc """
  Ash resource wrapping the existing `projects` table.

  Attribute multitenancy via `organization_id`. Write actions include `create`
  (with automatic TagDefinition creation), `update` (with tag name sync),
  `archive`, `unarchive`, and `destroy` (with tag cleanup).

  Read actions cover active/archived listings with optional ParadeDB search
  and session-duration aggregation, per-user project lookups, and ID-based
  fetches.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Changes.CleanupProjectTag
  alias Firmowid.Ash.Timetracker.Changes.CreateProjectTag
  alias Firmowid.Ash.Timetracker.Changes.SyncProjectTagName
  alias Firmowid.Ash.Timetracker.ProjectCosts
  alias Firmowid.Ash.Timetracker.ProjectUser
  alias Firmowid.Ash.Timetracker.Session
  alias Firmowid.Helpers.TimeConverter

  require Ash.Query
  require Resource

  postgres do
    table "projects"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :get, get_by: [:id]
    define :by_ids, args: [:ids]
    define :with_users
    define :for_user, args: [:user_id]
    define :active_for_user, args: [:user_id]
    define :list_active, args: [:date]

    define :list_archived
    define :create
    define :update
    define :archive
    define :unarchive
    define :destroy
    define :set_users, args: [:user_ids]
    define :project_total_cost, args: [:project_id, :date]
    define :project_total_cost_all_time, args: [:project_id]
    define :project_month_users_with_cost, args: [:project_id, :date]
    define :project_users_with_cost_all_time, args: [:project_id]
    define :project_users_with_removed, args: [:project_id]

    define :user_projects_with_duration, args: [:user_id, :date]
  end

  actions do
    defaults [:read]

    read :searchable do
      description "Read projects with optional ParadeDB full-text search on name."

      argument :search, :string

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch, columns: ~w(name), argument: :search}
    end

    # ── Read actions ──────────────────────────────────────────────────

    read :get do
      description "Get a single project by ID with users and counterparty preloaded."
      get? true

      prepare build(load: [:users, counterparty: [:display_label]])
    end

    read :by_ids do
      description "Fetch projects by a list of IDs."

      argument :ids, {:array, :uuid}, allow_nil?: false

      filter expr(id in ^arg(:ids))
    end

    read :with_users do
      description "All projects preloaded with their users."

      prepare build(load: [:users])
    end

    read :for_user do
      description "Projects that a specific user belongs to (via project_users join)."

      argument :user_id, :uuid, allow_nil?: false

      filter expr(exists(project_users, user_id == ^arg(:user_id)))
    end

    read :active_for_user do
      description "Active (non-archived) projects for a specific user, ordered by name."

      argument :user_id, :uuid, allow_nil?: false

      filter expr(is_nil(archived_at) and exists(project_users, user_id == ^arg(:user_id)))

      prepare build(sort: [name: :asc])
    end

    # ── List actions with duration aggregation ─────────────────────────

    action :list_active, {:array, :map} do
      description """
      Active projects with monthly session duration (hours). Supports optional
      ParadeDB search with BM25 relevance ordering.

      Uses Ash read with session duration aggregate, then Elixir-side hours
      conversion. ParadeDB search uses hardcoded `name @@@ ?` fragment
      (AshPostgres applies ::text casts to column references which breaks
      ParadeDB's @@@). Counterparty is loaded via Ash relationship.
      """

      argument :date, :date, allow_nil?: false
      argument :search, :string

      run fn input, context ->
        {:ok,
         read_projects_with_duration(
           _archived? = false,
           _all_time? = false,
           input.arguments.date,
           input.arguments[:search],
           context
         )}
      end
    end

    action :list_archived, {:array, :map} do
      description """
      Archived projects with all-time session duration (hours). Supports optional
      ParadeDB search. Same Ash read approach as :active.
      """

      argument :search, :string

      run fn input, context ->
        {:ok,
         read_projects_with_duration(
           _archived? = true,
           _all_time? = true,
           nil,
           input.arguments[:search],
           context
         )}
      end
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

    # ── Cost/reporting generic actions ─────────────────────────────────
    #
    # TODO: these cross-domain reporting actions (sessions × salaries × users)
    # are defined on Project but don't conceptually belong here. Consider moving
    # to a dedicated reporting resource or domain-level code interface.

    action :project_total_cost, :decimal do
      description """
      Total cost of work for a project in a given month. Returns nil when no salaries exist.

      Admin-only. Uses raw Ecto: cross-resource join of sessions (GROUP BY user_id)
      with a temporal salary subquery (DISTINCT ON user_id, salary active at month end).
      Rounds per-user time up to full hours, multiplies by hourly rate.
      Raw Ecto is required because the temporal DISTINCT ON salary lookup and the
      cross-resource aggregation (sessions × salaries) have no Ash equivalent.
      Organization scoping is explicit in the session subquery via Repo.get_org_id().
      """

      argument :project_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      run fn input, _context ->
        {:ok, ProjectCosts.compute_project_total_cost(input.arguments.project_id, input.arguments.date)}
      end
    end

    action :project_total_cost_all_time, :decimal do
      description """
      Total cost across all months for a project. Sums month-by-month costs.

      Admin-only. Uses Ash read (months_with_sessions via :month_start calculation)
      + raw Ecto cost computation per month (see :project_total_cost).
      """

      argument :project_id, :uuid, allow_nil?: false

      run fn input, context ->
        {:ok, ProjectCosts.compute_project_total_cost_all_time(input.arguments.project_id, context)}
      end
    end

    action :project_month_users_with_cost, {:array, :map} do
      description """
      Per-user time and cost for a project in a given month. Includes salary, avatar, removed status.

      Admin-only. Uses raw Ecto: 4-way join (User, ProjectUser, session subquery, HoursRecord)
      + per-user salary lookup via temporal DISTINCT ON subquery + Accounts avatar.
      Raw Ecto is required for the cross-resource joins and temporal salary lookup.
      Organization scoping via Repo.prepare_query on the outer users query.
      """

      argument :project_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      run fn input, _context ->
        {:ok,
         ProjectCosts.compute_project_month_users_with_cost(
           input.arguments.project_id,
           input.arguments.date
         )}
      end
    end

    action :project_users_with_cost_all_time, {:array, :map} do
      description """
      Per-user time and cost across all months for a project.

      Admin-only. Uses Ash read (months_with_sessions) + raw Ecto cost per month
      (see :project_month_users_with_cost), then merges per-user totals in Elixir.
      """

      argument :project_id, :uuid, allow_nil?: false

      run fn input, context ->
        {:ok,
         ProjectCosts.compute_project_users_with_cost_all_time(
           input.arguments.project_id,
           context
         )}
      end
    end

    action :project_users_with_removed, {:array, :map} do
      description """
      Users associated with a project — includes users who have sessions but were removed from the project.

      Admin-only. Uses raw Ecto: LEFT JOIN on Accounts.User ↔ ProjectUser with
      EXISTS subquery on sessions. Raw Ecto is required because Ash.Core.User is
      a read-only wrapper with no relationships to sessions or project_users.
      Organization scoping via Repo.prepare_query.
      """

      argument :project_id, :uuid, allow_nil?: false

      run fn input, _context ->
        {:ok, ProjectCosts.query_project_users_with_removed(input.arguments.project_id)}
      end
    end

    action :user_projects_with_duration, {:array, :map} do
      description """
      A user's projects with per-project session duration in a given month.

      Uses Ash reads with :for_user action + Ash.Query.aggregate for filtered
      duration sum. Passes actor and tenant through properly.
      """

      argument :user_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      run fn input, context ->
        {:ok, ProjectCosts.read_user_projects_with_duration(input, context)}
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy [action_type(:read), actor_attribute_equals(:role, :employee)] do
      authorize_if relates_to_actor_via([:project_users, :user])
    end

    # user_projects_with_duration uses Ash reads internally (passes actor/tenant,
    # enforces :for_user read policies). Any authenticated user may call it —
    # the internal :for_user read ensures employees only see their own projects.
    bypass action(:user_projects_with_duration) do
      authorize_if always()
    end

    # All other generic actions are admin-only. list_active/list_archived use Ash
    # reads with aggregates. Cost/reporting and project_users_with_removed use
    # raw Ecto for cross-resource joins. See each action's description.
    policy action_type(:action) do
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

  # ── Private helpers for duration-aggregated listings ──────────────────

  # Reads projects via Ash with a session duration aggregate, optional ParadeDB
  # search, and archive filtering. Returns `[%Project{hours: integer()}]`.
  defp read_projects_with_duration(archived?, all_time?, date, search, context) do
    ash_opts = [actor: context.actor, tenant: context.tenant]

    duration_filter = build_duration_filter(all_time?, date)

    search_args = if search in [nil, ""], do: %{}, else: %{search: search}

    results =
      __MODULE__
      |> Ash.Query.for_read(:searchable, search_args, ash_opts)
      |> apply_archive_filter(archived?)
      |> Ash.Query.aggregate(:duration, :sum, :sessions,
        field: :duration,
        default: 0,
        query: duration_filter
      )
      |> Ash.Query.load(counterparty: [:display_label])
      |> maybe_default_sort(search)
      |> Ash.read!(ash_opts)

    Firmowid.Repo.drop_paradedb_unnamed()

    Enum.map(results, fn project ->
      seconds = project.aggregates[:duration] || 0
      hours = TimeConverter.time_worked_in_seconds_to_hours(seconds)
      Map.put(project, :hours, hours)
    end)
  end

  defp build_duration_filter(true = _all_time?, _date), do: Ash.Query.new(Session)

  defp build_duration_filter(false, %Date{month: month, year: year}) do
    Ash.Query.filter(
      Session,
      fragment("extract(month from ?) = ?", start_datetime, ^month) and
        fragment("extract(year from ?) = ?", start_datetime, ^year)
    )
  end

  defp apply_archive_filter(query, true = _archived?) do
    Ash.Query.filter(query, not is_nil(archived_at))
  end

  defp apply_archive_filter(query, false) do
    Ash.Query.filter(query, is_nil(archived_at))
  end

  # When no search term is active, the preparation is a no-op so we apply
  # default alphabetical sorting. When search is active, the preparation
  # already sorts by pdb.score() relevance.
  defp maybe_default_sort(query, search) when search in [nil, ""] do
    Ash.Query.sort(query, name: :asc)
  end

  defp maybe_default_sort(query, _search), do: query

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
