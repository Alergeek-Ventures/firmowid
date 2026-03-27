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

  require Resource

  postgres do
    table "projects"
    repo(Firmowid.Repo)
    migrate?(false)
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

    # ── Read actions ──────────────────────────────────────────────────

    read :get do
      description "Get a single project by ID with users and counterparty preloaded."
      get? true

      prepare build(load: [:users, :counterparty])
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

    # All other generic actions are admin-only. active/archived_total use Ash
    # reads with aggregates. Cost/reporting and project_users_with_removed use
    # raw Ecto for cross-resource joins. See each action's description.
    policy action_type(:action) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end


  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute :name, :string do
      public?(true)
      allow_nil?(false)
      constraints(min_length: 2, max_length: 100)
    end

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

    has_many :sessions, Session
    has_many :project_users, ProjectUser

    many_to_many :users, Firmowid.Ash.Core.User do
      through(ProjectUser)
      source_attribute_on_join_resource(:project_id)
      destination_attribute_on_join_resource(:user_id)
    end

  end

  actions do
    defaults [:read]

    # ── Read actions ──────────────────────────────────────────────────

    read :get do
      description "Get a single project by ID with users and counterparty preloaded."
      get? true

      prepare build(load: [:users, :counterparty])
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

    action :active, {:array, :map} do
      description "Active projects with monthly session duration (hours). Supports optional ParadeDB search."

      argument :date, :date, allow_nil?: false
      argument :search, :string

      run fn input, _context ->
        list_projects_with_duration(
          _archived? = false,
          _all_time? = false,
          input.arguments.date,
          input.arguments[:search]
        )
      end
    end

    action :archived, {:array, :map} do
      description "Archived projects with monthly session duration (hours). Supports optional ParadeDB search."

      argument :date, :date, allow_nil?: false
      argument :search, :string

      run fn input, _context ->
        list_projects_with_duration(
          _archived? = true,
          _all_time? = false,
          input.arguments.date,
          input.arguments[:search]
        )
      end
    end

    action :archived_total, {:array, :map} do
      description "Archived projects with all-time session duration (hours). Supports optional ParadeDB search."

      argument :search, :string

      run fn input, _context ->
        list_projects_with_duration(
          _archived? = true,
          _all_time? = true,
          nil,
          input.arguments[:search]
        )
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

      run fn input, _context ->
        {:ok, set_project_users(input.arguments.project_id, input.arguments.user_ids)}
      end
    end

    # ── Cost/reporting generic actions ─────────────────────────────────

    action :project_total_cost, :decimal do
      description "Total cost of work for a project in a given month. Uses hourly rates active at month end, rounds per-user time up to full hours. Returns nil when no salaries exist."

      argument :project_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      run fn input, _context ->
        {:ok, ProjectCosts.compute_project_total_cost(input.arguments.project_id, input.arguments.date)}
      end
    end

    action :project_total_cost_all_time, :decimal do
      description "Total cost across all months for a project. Sums month-by-month costs."

      argument :project_id, :uuid, allow_nil?: false

      run fn input, _context ->
        {:ok, compute_project_total_cost_all_time(input.arguments.project_id)}
      end
    end

    action :project_month_users_with_cost, {:array, :map} do
      description "Per-user time and cost for a project in a given month. Includes salary, avatar, removed status."

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
      description "Per-user time and cost across all months for a project."

      argument :project_id, :uuid, allow_nil?: false

      run fn input, _context ->
        {:ok, compute_project_users_with_cost_all_time(input.arguments.project_id)}
      end
    end

    action :project_users_with_removed, {:array, :map} do
      description "Users associated with a project — includes users who have sessions but were removed from the project."

      argument :project_id, :uuid, allow_nil?: false

      run fn input, _context ->
        {:ok, ProjectCosts.query_project_users_with_removed(input.arguments.project_id)}
      end
    end

    action :project_users_with_sessions, {:array, :map} do
      description "Users with their sessions and total duration for a project."

      argument :project_id, :uuid, allow_nil?: false

      run fn input, _context ->
        {:ok, query_project_users_with_sessions(input.arguments.project_id)}
      end
    end

    action :user_projects_with_duration, {:array, :map} do
      description "A user's projects with per-project session duration in a given month."

      argument :user_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      run fn input, _context ->
        {:ok, compute_user_projects_with_duration(input.arguments.user_id, input.arguments.date)}
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

    belongs_to :counterparty, Firmowid.Ash.Core.Counterparty do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :tag_definition, Firmowid.Ash.Core.TagDefinition do
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

  defp list_projects_with_duration(archived?, all_time?, date, search) do
    import Ecto.Query

    session_schema = Session
    duration_subquery = build_duration_subquery(session_schema, all_time?, date)

    query =
      from(p in __MODULE__,
        left_join: sd in subquery(duration_subquery),
        on: p.id == sd.project_id,
        select: {p, sd.duration |> coalesce(0) |> type(:integer)}
      )

    query = apply_archive_filter(query, archived?)
    query = apply_search_and_order(query, search)

    results =
      query
      |> Firmowid.Repo.all(maybe_unnamed(search))
      |> Enum.map(fn {project, seconds} ->
        hours = seconds |> Kernel./(3600) |> Float.ceil() |> trunc()
        Map.put(project, :hours, hours)
      end)

    {:ok, results}
  end

  defp build_duration_subquery(session_schema, true = _all_time?, _date) do
    import Ecto.Query

    from(s in session_schema,
      group_by: s.project_id,
      select: %{
        project_id: s.project_id,
        duration:
          fragment(
            "SUM(EXTRACT(EPOCH FROM COALESCE(?, NOW()) - ?))::integer",
            s.end_datetime,
            s.start_datetime
          )
      }
    )
  end

  defp build_duration_subquery(session_schema, false, %Date{month: month, year: year}) do
    import Ecto.Query

    from(s in session_schema,
      where:
        fragment("EXTRACT(MONTH FROM ?) = ?", s.start_datetime, ^month) and
          fragment("EXTRACT(YEAR FROM ?) = ?", s.start_datetime, ^year),
      group_by: s.project_id,
      select: %{
        project_id: s.project_id,
        duration:
          fragment(
            "SUM(EXTRACT(EPOCH FROM COALESCE(?, NOW()) - ?))::integer",
            s.end_datetime,
            s.start_datetime
          )
      }
    )
  end

  defp apply_archive_filter(query, true = _archived?) do
    import Ecto.Query

    where(query, [p], not is_nil(p.archived_at))
  end

  defp apply_archive_filter(query, false) do
    import Ecto.Query

    where(query, [p], is_nil(p.archived_at))
  end

  defp apply_search_and_order(query, search) when search in [nil, ""] do
    import Ecto.Query

    order_by(query, [p], p.name)
  end

  defp apply_search_and_order(query, search) when is_binary(search) do
    import Ecto.Query

    Firmowid.Repo.put_paradedb_unnamed()

    query
    |> where([p], fragment("name @@@ ?", ^search))
    |> order_by([p], fragment("paradedb.score(?) DESC", p.id))
  end

  defp maybe_unnamed(search) when search in [nil, ""], do: []
  defp maybe_unnamed(_search), do: [prepare: :unnamed]

  # ── Private helpers for cost/reporting actions ───────────────────────

  defp salary_as_of_subquery(%Date{} = date) do
    import Ecto.Query

    as_of_date = Date.end_of_month(date)
    as_of_end_dt = DateTime.new!(as_of_date, ~T[23:59:59], "Etc/UTC")

    Firmowid.Ash.Payroll.UserSalary
    |> where([us], us.updated_at <= ^as_of_end_dt)
    |> where([us], is_nil(us.deleted_at) or us.deleted_at > ^as_of_date)
    |> order_by([us], asc: us.user_id, desc: us.updated_at)
    |> distinct([us], us.user_id)
    |> select([us], %{user_id: us.user_id, hourly_rate: us.hourly_rate})
  end

  defp compute_project_total_cost(project_id, %Date{} = date) do
    import Ecto.Query

    organization_id = Firmowid.Repo.get_org_id()

    session_summary =
      from(s in Session,
        where:
          s.project_id == ^project_id and
            s.organization_id == ^organization_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            fragment(
              "SUM(EXTRACT(EPOCH FROM COALESCE(?, NOW()) - ?))::integer",
              s.end_datetime,
              s.start_datetime
            )
        }
      )

    Firmowid.Repo.one(
      from(ss in subquery(session_summary),
        join: us in subquery(salary_as_of_subquery(date)),
        on: us.user_id == ss.user_id,
        select: fragment("SUM(? * CEIL(? / 3600.0))::numeric", us.hourly_rate, ss.time_worked)
      ),
      skip_organization_id: true
    )
  end

  defp compute_project_total_cost_all_time(project_id) do
    project_id
    |> query_months_with_sessions_by_project()
    |> Enum.reduce(nil, fn month_date, acc ->
      month_cost = compute_project_total_cost(project_id, month_date)
      add_nullable_decimals(acc, month_cost)
    end)
  end

  defp compute_project_month_users_with_cost(project_id, %Date{} = date) do
    alias Firmowid.Accounts
    alias Firmowid.Helpers.TimeConverter

    as_of_date = Date.end_of_month(date)

    project_id
    |> query_month_summary_by_project(date.month, date.year)
    |> Enum.map(fn %{user: u, time_worked: t, removed_from_project: r, hours_record: hr} ->
      salary = query_user_salary_as_of(u.id, as_of_date)
      hourly_rate = salary && salary.hourly_rate
      hours = TimeConverter.time_worked_in_seconds_to_hours(t)
      cost = hourly_rate && Decimal.mult(hourly_rate, Decimal.new(hours))

      u
      |> Accounts.get_user_with_avatar()
      |> Map.put(:time_worked, t)
      |> Map.put(:removed_from_project, r)
      |> Map.put(:expanded, false)
      |> Map.put(:hours_record, hr)
      |> Map.put(:salary, salary)
      |> Map.put(:hourly_rate, hourly_rate)
      |> Map.put(:cost, cost)
    end)
    |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})
  end

  defp compute_project_users_with_cost_all_time(project_id) do
    project_id
    |> query_months_with_sessions_by_project()
    |> Enum.reduce(%{}, fn month_date, acc ->
      project_id
      |> compute_project_month_users_with_cost(month_date)
      |> merge_month_users(acc)
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})
  end

  defp query_month_summary_by_project(project_id, month, year) do
    import Ecto.Query

    session_summary =
      from(s in Session,
        where:
          s.project_id == ^project_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            fragment(
              "SUM(EXTRACT(EPOCH FROM COALESCE(?, NOW()) - ?))::integer",
              s.end_datetime,
              s.start_datetime
            )
        }
      )

    Firmowid.Repo.all(
      from(u in Firmowid.Accounts.User,
        left_join: pu in ProjectUser,
        on: u.id == pu.user_id and pu.project_id == ^project_id,
        left_join: s in subquery(session_summary),
        on: u.id == s.user_id,
        left_join: hr in Firmowid.Ash.Timetracker.HoursRecord,
        on: u.id == hr.user_id and hr.month == ^month and hr.year == ^year,
        where: not is_nil(pu.id) or not is_nil(s.user_id),
        order_by: [u.name, u.email],
        select: %{
          user: u,
          time_worked: s.time_worked |> coalesce(0) |> type(:integer),
          removed_from_project: is_nil(pu.id),
          hours_record: hr
        }
      )
    )
  end

  defp query_project_users_with_removed(project_id) do
    import Ecto.Query

    session_users_query =
      from(s in Session,
        where: s.project_id == ^project_id and s.user_id == parent_as(:user).id,
        select: 1
      )

    Firmowid.Repo.all(
      from(u in Firmowid.Accounts.User,
        as: :user,
        left_join: pu in ProjectUser,
        on: u.id == pu.user_id and pu.project_id == ^project_id,
        where: exists(session_users_query) or not is_nil(pu.id),
        order_by: [u.name, u.email],
        select: %{user: u, removed_from_project: is_nil(pu.id)}
      )
    )
  end

  defp query_project_users_with_sessions(project_id) do
    import Ecto.Query

    users = query_project_users_with_removed(project_id)
    user_ids = Enum.map(users, & &1.user.id)

    sessions_grouped =
      from(s in Session,
        where: s.project_id == ^project_id and s.user_id in ^user_ids,
        select: s
      )
      |> Firmowid.Repo.all()
      |> Enum.group_by(& &1.user_id)

    Enum.map(users, fn %{user: user, removed_from_project: removed} ->
      user_sessions = Map.get(sessions_grouped, user.id, [])

      time_worked =
        Enum.reduce(user_sessions, 0, fn s, acc ->
          acc + compute_session_duration(s)
        end)

      %{
        user: user,
        removed_from_project: removed,
        time_worked: time_worked,
        sessions: user_sessions
      }
    end)
  end

  defp compute_session_duration(%{end_datetime: nil, start_datetime: start}) do
    DateTime.diff(DateTime.utc_now(), start, :second)
  end

  defp compute_session_duration(%{end_datetime: end_dt, start_datetime: start}) do
    DateTime.diff(end_dt, start, :second)
  end

  defp compute_user_projects_with_duration(user_id, %Date{} = date) do
    import Ecto.Query

    # Get all projects for the user
    projects =
      Firmowid.Repo.all(
        from(p in __MODULE__,
          join: pu in ProjectUser,
          on: p.id == pu.project_id,
          where: pu.user_id == ^user_id,
          select: p
        )
      )

    # Get per-project duration in the given month
    duration_map =
      from(s in Session,
        where:
          s.user_id == ^user_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.project_id,
        select: {
          s.project_id,
          fragment(
            "SUM(EXTRACT(EPOCH FROM COALESCE(?, NOW()) - ?))::integer",
            s.end_datetime,
            s.start_datetime
          )
        }
      )
      |> Firmowid.Repo.all()
      |> Map.new()

    projects
    |> Enum.map(&Map.put(&1, :duration, Map.get(duration_map, &1.id, 0)))
    |> Enum.sort_by(& &1.duration, :desc)
  end

  defp query_months_with_sessions_by_project(project_id) do
    import Ecto.Query

    from(s in Session,
      where: s.project_id == ^project_id,
      select:
        "date_trunc('month', ?)"
        |> fragment(s.start_datetime)
        |> selected_as(:date),
      distinct: [desc: selected_as(:date)],
      order_by: [desc: selected_as(:date)]
    )
    |> Firmowid.Repo.all()
    |> Enum.map(&month_value_to_date/1)
  end

  defp query_user_salary_as_of(user_id, %Date{} = date) do
    import Ecto.Query

    date
    |> salary_as_of_subquery()
    |> where([us], us.user_id == ^user_id)
    |> Firmowid.Repo.one(skip_organization_id: true)
  end

  defp month_value_to_date(%Date{} = date), do: Date.beginning_of_month(date)

  defp month_value_to_date(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_date() |> Date.beginning_of_month()

  defp month_value_to_date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.beginning_of_month()

  defp add_nullable_decimals(nil, nil), do: nil
  defp add_nullable_decimals(nil, b), do: b
  defp add_nullable_decimals(a, nil), do: a
  defp add_nullable_decimals(a, b), do: Decimal.add(a, b)

  defp merge_month_users(month_users, acc) do
    Enum.reduce(month_users, acc, fn user, users_acc ->
      Map.update(users_acc, user.id, all_time_user_from_month(user), fn existing ->
        merge_all_time_user(existing, user)
      end)
    end)
  end

  defp all_time_user_from_month(user) do
    user
    |> Map.put(:expanded, false)
    |> Map.put(:hourly_rate, nil)
    |> Map.put(:salary, nil)
    |> Map.put(:hours_record, nil)
  end

  defp merge_all_time_user(existing, month_user) do
    cost = add_nullable_decimals(existing.cost, month_user.cost)

    existing
    |> Map.put(:time_worked, existing.time_worked + month_user.time_worked)
    |> Map.put(:cost, cost)
    |> Map.put(:expanded, false)
  end

  # ── Private helpers for user assignment ──────────────────────────────

  defp set_project_users(project_id, user_ids) do
    import Ecto.Query

    existing =
      Firmowid.Repo.all(
        from(pu in ProjectUser,
          where: pu.project_id == ^project_id,
          select: pu
        )
      )

    existing_user_ids = MapSet.new(existing, & &1.user_id)
    desired_user_ids = MapSet.new(user_ids)

    to_add = MapSet.difference(desired_user_ids, existing_user_ids)
    to_remove = MapSet.difference(existing_user_ids, desired_user_ids)

    org_id = Firmowid.Repo.get_org_id()

    # Remove users no longer in the set
    if !Enum.empty?(to_remove) do
      remove_ids = MapSet.to_list(to_remove)

      ProjectUser
      |> where([pu], pu.project_id == ^project_id and pu.user_id in ^remove_ids)
      |> Firmowid.Repo.delete_all()
    end

    # Add new users
    for uid <- to_add do
      Firmowid.Repo.insert!(
        %ProjectUser{
          id: Ash.UUIDv7.generate(),
          project_id: project_id,
          user_id: uid,
          organization_id: org_id
        },
        skip_organization_id: true
      )
    end

    :ok
  end
end
