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

  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Ash.Timetracker.Checks.OwnsResource
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
      description "Sessions grouped by title for a user+project+month/year, returning title + sum duration (seconds)."

      argument :user_id, :uuid, allow_nil?: false
      argument :project_id, :uuid, allow_nil?: false
      argument :month, :integer, allow_nil?: false
      argument :year, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, query_grouped_user_project_sessions(input.arguments)}
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
      description "CSV of tasks (grouped sessions) for a project in a given month, with duration in ceiled hours."

      argument :project_id, :uuid, allow_nil?: false
      argument :month, :integer, allow_nil?: false
      argument :year, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, query_project_tasks_csv(input.arguments)}
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

    # TODO: Generic actions use raw Ecto queries that bypass per-record read
    # policies. While action dispatch is authorized here, the data fetched
    # inside is not ownership-scoped. Callers always pass actor's user_id,
    # but that's enforced by the caller, not the policy. Phase 3 will replace
    # raw Ecto with Ash.read (which enforces :read policies), at which point
    # we can tighten this further. Until then, the risk is limited to
    # aggregate stats (total seconds, week dates) — not individual records.
    policy [action_type(:action), actor_attribute_equals(:role, :employee)] do
      authorize_if always()
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

    has_many :hours_records, Firmowid.Ash.Timetracker.HoursRecord do
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

  defp query_grouped_user_project_sessions(args) do
    import Ecto.Query

    %{user_id: user_id, project_id: project_id, month: month, year: year} = args

    Firmowid.Repo.all(
      from(s in __MODULE__,
        where:
          s.user_id == ^user_id and s.project_id == ^project_id and
            fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
            fragment("extract(year from ?) = ?", s.start_datetime, ^year),
        group_by: s.title,
        order_by: [desc: selected_as(:time_worked)],
        select: %{
          title: s.title,
          duration:
            "extract(epoch from coalesce(?, now()) - ?)"
            |> fragment(s.end_datetime, s.start_datetime)
            |> sum()
            |> type(:integer)
            |> selected_as(:time_worked)
        }
      )
    )
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

  defp query_project_tasks_csv(args) do
    import Ecto.Query

    %{project_id: project_id, month: month, year: year} = args

    from(s in __MODULE__,
      where:
        s.project_id == ^project_id and
          fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
          fragment("extract(year from ?) = ?", s.start_datetime, ^year),
      group_by: s.title,
      order_by: [desc: selected_as(:time_worked)],
      select: %{
        title: s.title,
        duration:
          "extract(epoch from coalesce(?, now()) - ?)"
          |> fragment(s.end_datetime, s.start_datetime)
          |> sum()
          |> type(:integer)
          |> selected_as(:time_worked)
      }
    )
    |> Firmowid.Repo.all()
    |> Enum.map(fn task ->
      %{task | duration: ceil(task.duration / 3600)}
    end)
    |> CSV.encode(headers: [title: "Zadanie", duration: "Czas trwania (godziny)"])
    |> Enum.join()
  end
end
