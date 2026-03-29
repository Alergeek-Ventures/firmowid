defmodule Firmowid.Ash.Timetracker.Session do
  @moduledoc """
  Ash resource wrapping the existing `sessions` table.

  Attribute multitenancy via `organization_id`. Write actions include `start`
  (begins a new session), `stop` (ends a running session), `create` (full attrs),
  `update`, and `destroy`. Overlap is enforced by a DB trigger — the resulting
  Postgrex error is surfaced as-is by AshPostgres.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ecto.Query, warn: false

  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Ash.Timetracker.Checks.OwnsResource
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Ash.Timetracker.Project
  alias Firmowid.Ash.Timetracker.Validations.DatetimeOrder
  alias Firmowid.Ash.Timetracker.Validations.ProjectAccess
  alias Firmowid.Helpers.TimeConverter

  require Ash.Query
  require Resource

  postgres do
    table "sessions"
    repo(Firmowid.Repo)
    migrate?(false)
  end

  code_interface do
    define :list_user_sessions, args: [:user_id]
    define :get_current
    define :most_recent, args: [:user_id]
    define :by_ids, args: [:ids]
    define :list_overlapping, args: [:user_id, :start_datetime]
    define :start
    define :stop
    define :create
    define :update
    define :destroy
    define :weeks_with_sessions, args: [:user_id]
    define :grouped_user_project_sessions, args: [:user_id, :project_id, :month, :year]
    define :months_with_sessions
    define :total_time_worked
    define :project_tasks_csv, args: [:project_id, :month, :year]
    define :list_employees_for_month, args: [:date]
    define :employee_details, args: [:user_id, :date]
  end

  actions do
    defaults [:read, :destroy]

    # ── Read actions ──────────────────────────────────────────────────

    read :list_user_sessions do
      description "List a user's sessions, optionally filtered to those starting on or after a date."

      argument :user_id, :uuid, allow_nil?: false
      argument :after_date, :date

      prepare build(sort: [start_datetime: :desc], load: [:duration, :lockdown])

      filter expr(user_id == ^arg(:user_id))

      prepare fn query, _context ->
        case Ash.Query.get_argument(query, :after_date) do
          nil ->
            query

          date ->
            dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
            Ash.Query.do_filter(query, start_datetime: [greater_than_or_equal: dt])
        end
      end
    end

    read :get_current do
      description "Get the currently running session (no end_datetime) for the acting user."
      get? true

      prepare build(sort: [start_datetime: :desc], limit: 1, load: [:duration])

      filter expr(is_nil(end_datetime))

      prepare fn query, context ->
        case context.actor do
          %{id: actor_id} -> Ash.Query.do_filter(query, user_id: actor_id)
          _ -> query
        end
      end
    end

    read :most_recent do
      description "Get the most recent session for a user."
      get? true

      argument :user_id, :uuid, allow_nil?: false

      prepare build(sort: [start_datetime: :desc], limit: 1)

      filter expr(user_id == ^arg(:user_id))
    end

    read :by_ids do
      description "Fetch sessions by a list of IDs."

      argument :ids, {:array, :uuid}, allow_nil?: false

      prepare build(load: [:duration])

      filter expr(id in ^arg(:ids))
    end

    read :list_overlapping do
      description """
      Find sessions that overlap with a given time range for a user.

      Used for pre-save conflict detection. See `filter_overlap/3` for the
      overlap predicate that mirrors the DB trigger.
      """

      argument :user_id, :uuid, allow_nil?: false
      argument :start_datetime, :utc_datetime, allow_nil?: false
      argument :end_datetime, :utc_datetime
      argument :exclude_id, :uuid

      prepare build(sort: [start_datetime: :asc], load: [:duration, :lockdown])

      filter expr(user_id == ^arg(:user_id))

      prepare fn query, _context ->
        exclude_id = Ash.Query.get_argument(query, :exclude_id)
        new_end = Ash.Query.get_argument(query, :end_datetime)

        query
        |> maybe_exclude_id(exclude_id)
        |> filter_overlap(Ash.Query.get_argument(query, :start_datetime), new_end)
      end
    end

    # ── Write actions ─────────────────────────────────────────────────

    create :start do
      description "Start a new time tracking session (auto-sets start_datetime to now)."
      accept [:title, :project_id, :is_remote]

      change set_attribute(:start_datetime, &DateTime.utc_now/0)
      change relate_actor(:user)
    end

    create :create do
      description "Create a session with explicit attributes (for import or admin use)."
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote, :user_id]
    end

    update :stop do
      description "Stop a running session by setting end_datetime to now."
      accept []
      require_atomic? false

      change set_attribute(:end_datetime, &DateTime.utc_now/0)
    end

    update :update do
      description "Update session attributes."
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote]
      require_atomic? false
    end

    # ── Generic actions (non-standard return shapes) ──────────────────

    action :weeks_with_sessions, {:array, :date} do
      description "Distinct weeks (as Monday dates) that have sessions for a user."

      argument :user_id, :uuid, allow_nil?: false
      argument :after_date, :date
      argument :limit, :integer
      argument :timezone, :string, default: "Etc/UTC"

      run fn input, context ->
        {:ok, read_weeks_with_sessions(input.arguments, context)}
      end
    end

    action :grouped_user_project_sessions, {:array, :map} do
      description """
      Sessions grouped by title for a user+project+month/year, returning
      `[%{title: String.t(), duration: integer()}]` sorted by duration desc.

      Uses Ash read with `:duration` calculation, then Elixir-side grouping.
      Read policies and multitenancy are enforced by the Ash read layer.
      Employee access is additionally restricted to own sessions via actor check.
      """

      argument :user_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :month, :integer, allow_nil?: false
      argument :year, :integer, allow_nil?: false

      run fn input, context ->
        enforce_own_sessions!(context.actor, input.arguments.user_id)

        sessions =
          read_sessions_grouped_by_title(
            input.arguments.month,
            input.arguments.year,
            context,
            user_id: input.arguments.user_id,
            project_id: input.arguments.project_id
          )

        {:ok, sessions}
      end
    end

    action :months_with_sessions, {:array, :naive_datetime} do
      description "Distinct months (as date_trunc values) that have sessions. Optionally filtered by user or project."

      argument :user_id, :uuid
      argument :project_id, :uuid

      run fn input, context ->
        {:ok, read_months_with_sessions(input.arguments, context)}
      end
    end

    action :total_time_worked, :integer do
      description "Sum of session durations (seconds). When month/year are given, scoped to that month; when omitted, all-time. Optionally filtered by user and/or project."

      argument :month, :integer
      argument :year, :integer
      argument :user_id, :uuid
      argument :project_id, :uuid

      run fn input, context ->
        {:ok, aggregate_total_time_worked(input.arguments, context)}
      end
    end

    action :project_tasks_csv, :string do
      description """
      CSV of tasks (grouped sessions) for a project in a given month, with
      duration in ceiled hours. Admin-only.

      Uses Ash read with `:duration` calculation, then Elixir-side grouping
      and CSV encoding. Read policies and multitenancy enforced by Ash.
      """

      argument :project_id, :uuid, allow_nil?: false
      argument :month, :integer, allow_nil?: false
      argument :year, :integer, allow_nil?: false

      run fn input, context ->
        csv =
          input.arguments.month
          |> read_sessions_grouped_by_title(
            input.arguments.year,
            context,
            project_id: input.arguments.project_id
          )
          |> Enum.map(fn task ->
            %{task | duration: TimeConverter.time_worked_in_seconds_to_hours(task.duration)}
          end)
          |> CSV.encode(headers: [title: "Zadanie", duration: "Czas trwania (godziny)"])
          |> Enum.join()

        {:ok, csv}
      end
    end

    action :list_employees_for_month, {:array, :map} do
      description """
      Admin-only. Returns employee data for a given month: user, hours record,
      hourly rate, and total time worked. Cross-domain join
      (User × Session × HoursRecord × UserSalary) via raw Ecto.

      Replaces the former `Management.list_employees/3` context function.
      Organization scoping uses `Repo.put_org_id` bridge for the raw Ecto
      queries; Ash policy enforcement gates access to admins.
      """

      argument :date, :date, allow_nil?: false
      argument :archived, :boolean, default: false
      argument :search, :string, default: ""

      run fn input, context ->
        {:ok, query_employees_for_month(input.arguments, context)}
      end
    end

    action :employee_details, :map do
      description """
      Admin-only. Returns a single employee's details for a given month:
      user with projects (each with grouped sessions), hourly rate,
      hours record, and total time worked.

      Replaces the former `Management.list_employee_details/2` context function.
      Returns `nil` when the user is not found.
      """

      argument :user_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      run fn input, context ->
        {:ok, find_employee_details(input.arguments, context)}
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy [action_type(:read), actor_attribute_equals(:role, :employee)] do
      authorize_if relates_to_actor_via(:user)
    end

    # Stopping a running session is always allowed (the old Bodyguard rule
    # checked `end_datetime == nil` to bypass lockdown).
    policy [action(:stop), actor_attribute_equals(:role, :employee)] do
      authorize_if relates_to_actor_via(:user)
    end

    # Create: employee can only create sessions for themselves.
    # `relates_to_actor_via` can't filter on creates, so we check the
    # changeset attribute directly via a simple check.
    policy [action_type(:create), actor_attribute_equals(:role, :employee)] do
      forbid_unless HoursRecordNotSubmitted
      authorize_if OwnsResource
    end

    # Update/destroy: session must belong to the actor and month not submitted.
    policy [
      action_type([:update, :destroy]),
      actor_attribute_equals(:role, :employee)
    ] do
      forbid_unless HoursRecordNotSubmitted
      authorize_if relates_to_actor_via(:user)
    end

    # Generic actions that employees can call. These use Ash reads internally
    # (which enforce :read policies). grouped_user_project_sessions additionally
    # has an in-action actor check (enforce_own_sessions!) to prevent employees
    # from querying other users' data.
    #
    # TODO: replace `authorize_if always()` with proper per-action policies once
    # these generic actions can be expressed as Ash reads with aggregates. The
    # current pattern relies on internal Ash reads for security — safe but should
    # not be copied blindly to new domains.
    policy [
      action([
        :weeks_with_sessions,
        :months_with_sessions,
        :total_time_worked,
        :grouped_user_project_sessions
      ]),
      actor_attribute_equals(:role, :employee)
    ] do
      authorize_if always()
    end

    # Admin-only generic actions — they aggregate data across all users.
    policy [
      action([:project_tasks_csv, :list_employees_for_month, :employee_details]),
      actor_attribute_equals(:role, :employee)
    ] do
      forbid_if always()
    end
  end

  validations do
    validate {DatetimeOrder, start_field: :start_datetime, end_field: :end_datetime},
      on: [:create, :update]

    validate {ProjectAccess, []},
      on: [:create, :update],
      where: [changing(:project_id)]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false
    attribute :start_datetime, :utc_datetime, public?: true, allow_nil?: false
    attribute :end_datetime, :utc_datetime, public?: true
    attribute :is_remote, :boolean, public?: true, default: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :project, Project do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    # fragment() is required here because Ash expressions don't have a built-in
    # EXTRACT function. The alternative would be adding month/year calculations
    # to Session, but that's a larger refactor for a simple join condition.
    has_many :hours_records, HoursRecord do
      no_attributes? true

      description "HoursRecords matching this session's user, month, year, and org — used for lockdown checks."

      filter expr(
               user_id == parent(user_id) and
                 organization_id == parent(organization_id) and
                 month == fragment("EXTRACT(MONTH FROM ?)::integer", parent(start_datetime)) and
                 year == fragment("EXTRACT(YEAR FROM ?)::integer", parent(start_datetime))
             )
    end
  end

  calculations do
    calculate :duration,
              :integer,
              expr(
                if is_nil(end_datetime) do
                  fragment("EXTRACT(EPOCH FROM (NOW() - ?))::integer", start_datetime)
                else
                  fragment("EXTRACT(EPOCH FROM (? - ?))::integer", end_datetime, start_datetime)
                end
              ) do
      public? true
    end

    calculate :month_start,
              :naive_datetime,
              expr(fragment("date_trunc('month', ?)", start_datetime)) do
      description "First day of the month this session belongs to (truncated start_datetime)."
    end

    calculate :week_start,
              :naive_datetime,
              expr(fragment("date_trunc('week', ?)", start_datetime)) do
      description "Monday of the week this session belongs to (ISO week, truncated start_datetime)."
    end

    calculate :lockdown,
              :boolean,
              expr(exists(hours_records, true)) do
      public? true

      description "Whether an hours record has been submitted for this session's month, locking edits."
    end
  end

  # ── Private helpers for generic actions ──────────────────────────────
  #
  # TODO: extract these imperative helpers into a dedicated SessionQueries
  # module (similar to how ProjectCosts was extracted from Project) to keep
  # the resource module focused on Ash DSL declarations.

  # Ensures employees can only query their own sessions in generic actions.
  # While the underlying Ash reads enforce :read policies (own sessions only),
  # this provides an explicit fail-fast check. Admins may query any user's data.
  #
  # Hand-rolled instead of using Ash policies because generic actions don't
  # receive a query/changeset that the policy engine can filter on — they
  # operate on arbitrary return types (:map, {:array, :map}). Replace with a
  # dedicated read action + policies once these reporting queries can be
  # expressed as Ash reads with aggregates.
  defp enforce_own_sessions!(%{role: :admin}, _user_id), do: :ok

  defp enforce_own_sessions!(%{id: actor_id}, user_id) when actor_id == user_id, do: :ok

  defp enforce_own_sessions!(_actor, _user_id) do
    raise Ash.Error.Forbidden,
      errors: ["employees can only access their own sessions"]
  end

  defp read_weeks_with_sessions(args, context) do
    ash_opts = [actor: context.actor, tenant: context.tenant]
    timezone = args[:timezone] || "Etc/UTC"

    query =
      __MODULE__
      |> Ash.Query.filter(user_id == ^args.user_id)
      |> maybe_filter_before_date(args[:after_date])
      |> Ash.Query.distinct(:week_start)
      |> Ash.Query.distinct_sort(week_start: :desc)
      |> Ash.Query.sort(week_start: :desc)
      |> Ash.Query.load(:week_start)
      |> maybe_limit(args[:limit])

    query
    |> Ash.read!(ash_opts)
    |> Enum.map(fn session ->
      session.week_start
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()
    end)
  end

  defp maybe_filter_before_date(query, nil), do: query

  defp maybe_filter_before_date(query, %Date{} = date) do
    dt = DateTime.new!(date, ~T[00:00:00])
    Ash.Query.filter(query, start_datetime < ^dt)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: Ash.Query.limit(query, limit)

  # Reads sessions for the given month/year, groups by title, and sums the
  # `:duration` calculation. Returns `[%{title: String.t(), duration: integer()}]`
  # sorted by duration descending. Accepts optional `user_id:` and `project_id:`
  # keyword filters.
  defp read_sessions_grouped_by_title(month, year, context, filters) do
    ash_opts = [actor: context.actor, tenant: context.tenant]

    __MODULE__
    |> maybe_filter_month_year(month, year)
    |> maybe_filter(:user_id, filters[:user_id])
    |> maybe_filter(:project_id, filters[:project_id])
    |> Ash.Query.load(:duration)
    |> Ash.read!(ash_opts)
    |> Enum.group_by(& &1.title)
    |> Enum.map(fn {title, sessions} ->
      %{title: title, duration: sessions |> Enum.map(& &1.duration) |> Enum.sum()}
    end)
    |> Enum.sort_by(& &1.duration, :desc)
  end

  defp read_months_with_sessions(args, context) do
    ash_opts = [actor: context.actor, tenant: context.tenant]

    __MODULE__
    |> maybe_filter(:user_id, args[:user_id])
    |> maybe_filter(:project_id, args[:project_id])
    |> Ash.Query.distinct(:month_start)
    |> Ash.Query.distinct_sort(month_start: :desc)
    |> Ash.Query.sort(month_start: :desc)
    |> Ash.Query.load(:month_start)
    |> Ash.read!(ash_opts)
    |> Enum.map(& &1.month_start)
  end

  defp aggregate_total_time_worked(args, context) do
    ash_opts = [actor: context.actor, tenant: context.tenant]

    query =
      __MODULE__
      |> maybe_filter_month_year(args[:month], args[:year])
      |> maybe_filter(:user_id, args[:user_id])
      |> maybe_filter(:project_id, args[:project_id])

    %{total: total} =
      Ash.aggregate!(query, {:total, :sum, field: :duration, default: 0}, ash_opts)

    total
  end

  defp maybe_filter_month_year(query, month, year) when is_integer(month) and is_integer(year) do
    Ash.Query.filter(
      query,
      fragment("extract(month from ?) = ?", start_datetime, ^month) and
        fragment("extract(year from ?) = ?", start_datetime, ^year)
    )
  end

  defp maybe_filter_month_year(query, _, _), do: query

  defp maybe_filter(query, :user_id, nil), do: query
  defp maybe_filter(query, :user_id, uid), do: Ash.Query.filter(query, user_id == ^uid)

  defp maybe_filter(query, :project_id, nil), do: query
  defp maybe_filter(query, :project_id, pid), do: Ash.Query.filter(query, project_id == ^pid)

  # ── Employee management helpers (admin-only generic actions) ──────────
  #
  # Cross-domain joins (User × Session × HoursRecord × UserSalary) via raw
  # Ecto. Organization scoping uses the Repo.put_org_id bridge — explicit
  # here so these survive if `disable_async?` is ever turned off.
  #
  # Ported from the former Firmowid.Management context module.

  defp query_employees_for_month(args, context) do
    %{date: date, archived: archived, search: search} = args

    # Bridge: ensure process-dict org scoping for raw Ecto queries
    Firmowid.Repo.put_org_id(context.tenant)

    time_worked_query =
      from(s in __MODULE__,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year),
        group_by: s.user_id,
        select: %{
          user_id: s.user_id,
          time_worked:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }
      )

    # TODO: add database support for archived users — the `archived` argument
    # is accepted but the User schema has no `archived` column yet. The filter
    # below is a compile-time constant expression (no-op). When the column is
    # added, replace with: `where: u.archived == ^archived`.
    from(u in Firmowid.Accounts.User,
      where: ^archived == false,
      left_join: us in subquery(UserSalary.salary_as_of_subquery(date, context.tenant)),
      on: us.user_id == u.id,
      left_join: s in subquery(time_worked_query),
      on: s.user_id == u.id,
      left_join: hr in HoursRecord,
      on: hr.user_id == u.id and hr.year == ^date.year and hr.month == ^date.month,
      select: %{
        user: u,
        hours_record: hr,
        hourly_rate: us.hourly_rate,
        time_worked: coalesce(s.time_worked, 0)
      }
    )
    |> filter_employee_search(search)
    |> Firmowid.Repo.all()
  end

  defp filter_employee_search(query, ""), do: query
  defp filter_employee_search(query, nil), do: query

  defp filter_employee_search(query, search) do
    sanitized =
      search
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    where(
      query,
      [user],
      ilike(user.name, ^"%#{sanitized}%") or ilike(user.email, ^"%#{sanitized}%")
    )
  end

  defp find_employee_details(args, context) do
    %{user_id: user_id, date: date} = args

    # Bridge: ensure process-dict org scoping for raw Ecto queries
    Firmowid.Repo.put_org_id(context.tenant)

    sessions_query =
      from(s in __MODULE__,
        where:
          fragment("extract(month from ?) = ?", s.start_datetime, ^date.month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^date.year) and
            s.user_id == ^user_id,
        group_by: [s.user_id, s.project_id, s.title],
        select: %{
          title: s.title,
          project_id: s.project_id,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> coalesce(0)
            |> type(:integer)
        }
      )

    Firmowid.Accounts.User
    |> Firmowid.Repo.get(user_id)
    |> Firmowid.Repo.preload(sessions: sessions_query)
    |> case do
      nil ->
        nil

      user ->
        hourly_rate =
          case employee_salary_as_of(user_id, date, context.tenant) do
            nil -> Decimal.new(0)
            %{hourly_rate: rate} -> rate
          end

        hours_record = employee_hours_record(user_id, date)

        # Group sessions by project and attach to manually loaded projects.
        # We can't use Repo.preload(projects: [sessions: fn ...]) because
        # Ash resources use Ash.NotLoaded (not Ecto.Association.NotLoaded)
        # which confuses Ecto's preload logic.
        sessions_by_project = Enum.group_by(user.sessions, & &1.project_id)

        projects =
          user
          |> Firmowid.Repo.preload(:projects)
          |> Map.get(:projects)
          |> Enum.map(fn project ->
            Map.put(project, :sessions, Map.get(sessions_by_project, project.id, []))
          end)

        user
        |> Map.put(:projects, projects)
        |> Map.put(:hourly_rate, hourly_rate)
        |> Map.put(:hours_record, hours_record)
        |> Map.put(:time_worked, user.sessions |> Enum.map(& &1.duration) |> Enum.sum())
    end
  end

  defp employee_salary_as_of(user_id, date, tenant) do
    date
    |> UserSalary.salary_as_of_subquery(tenant)
    |> where([us], us.user_id == ^user_id)
    |> Firmowid.Repo.one(skip_organization_id: true)
  end

  defp employee_hours_record(user_id, date) do
    HoursRecord
    |> where([hr], hr.user_id == ^user_id)
    |> where([hr], hr.month == ^date.month and hr.year == ^date.year)
    |> Firmowid.Repo.one()
  end

  # ── Overlap query helpers ─────────────────────────────────────────────

  defp maybe_exclude_id(query, nil), do: query
  defp maybe_exclude_id(query, id), do: Ash.Query.filter(query, id != ^id)

  # Mirrors the DB trigger: start < COALESCE(new_end, 'infinity') AND COALESCE(end, 'infinity') > new.start
  #
  # We use a far-future sentinel instead of Postgres 'infinity' because Ash expressions
  # don't support the 'infinity' timestamp literal. The sentinel must exceed any realistic
  # session end time. This is safe because the DB trigger uses actual 'infinity' as the
  # authoritative constraint — this filter is only for the pre-save overlap query.
  @open_end_sentinel ~U[9999-12-31 23:59:59Z]

  defp filter_overlap(query, new_start, nil) do
    # New session has no end (running) — overlaps anything that hasn't ended before new_start
    Ash.Query.filter(
      query,
      # if/3 is Ash expression syntax (ternary), not Elixir's if/do — parentheses are required.
      # credo:disable-for-next-line Credo.Check.Readability.ParenthesesInCondition
      if(is_nil(end_datetime), ^@open_end_sentinel, end_datetime) > ^new_start
    )
  end

  # credo:disable-for-lines:5 Credo.Check.Readability.ParenthesesInCondition
  defp filter_overlap(query, new_start, new_end) do
    Ash.Query.filter(
      query,
      start_datetime < ^new_end and
        if(is_nil(end_datetime), ^@open_end_sentinel, end_datetime) > ^new_start
    )
  end
end
