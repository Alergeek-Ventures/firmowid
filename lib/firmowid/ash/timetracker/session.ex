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

  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Ash.Timetracker.Checks.OwnsResource
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Ash.Timetracker.Project
  alias Firmowid.Ash.Timetracker.Validations.DatetimeOrder
  alias Firmowid.Ash.Timetracker.Validations.ProjectAccess

  require Ash.Query
  require Resource

  postgres do
    table "sessions"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :list_user_sessions, args: [:user_id]
    define :get_current
    define :most_recent, args: [:user_id]
    define :list_overlapping, args: [:user_id, :start_datetime]
    define :start
    define :stop
    define :create
    define :update
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    # ── Read actions ──────────────────────────────────────────────────

    read :list do
      description """
      Flexible session listing with optional filters.
      Sorting, loading (duration, lockdown, month_start, week_start), and
      aggregation controlled at callsite.
      """

      argument :user_id, :uuid
      argument :project_id, :uuid
      argument :month, :integer
      argument :year, :integer
      argument :running_only, :boolean
      argument :ids, {:array, :uuid}

      prepare build(filter: expr(user_id == ^arg(:user_id))) do
        where present(:user_id)
      end

      prepare build(filter: expr(project_id == ^arg(:project_id))) do
        where present(:project_id)
      end

      prepare build(
                filter:
                  expr(
                    fragment("extract(month from ?) = ?", start_datetime, ^arg(:month)) and
                      fragment("extract(year from ?) = ?", start_datetime, ^arg(:year))
                  )
              ) do
        where [present(:month), present(:year)]
      end

      prepare build(filter: expr(is_nil(end_datetime))) do
        where argument_equals(:running_only, true)
      end

      prepare build(filter: expr(id in ^arg(:ids))) do
        where present(:ids)
      end
    end

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
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # System actors have no access to employee timetracking data
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # Employee policies: own sessions only
    policy [action_type(:read), actor_attribute_equals(:role, :employee)] do
      authorize_if relates_to_actor_via(:user)
    end

    # :invoicing and :accountant — timetracking is personal, same as employee
    policy [action_type(:read), {AtLeastRole, role: :invoicing}] do
      authorize_if relates_to_actor_via(:user)
    end

    # Stopping a running session is always allowed (the old Bodyguard rule
    # checked `end_datetime == nil` to bypass lockdown).
    policy [action(:stop), actor_attribute_equals(:role, :employee)] do
      authorize_if relates_to_actor_via(:user)
    end

    policy [action(:stop), {AtLeastRole, role: :invoicing}] do
      authorize_if relates_to_actor_via(:user)
    end

    # Create: employee can only create sessions for themselves.
    # `relates_to_actor_via` can't filter on creates, so we check the
    # changeset attribute directly via a simple check.
    policy [action_type(:create), actor_attribute_equals(:role, :employee)] do
      forbid_unless HoursRecordNotSubmitted
      authorize_if OwnsResource
    end

    policy [action_type(:create), {AtLeastRole, role: :invoicing}] do
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

    policy [
      action_type([:update, :destroy]),
      {AtLeastRole, role: :invoicing}
    ] do
      forbid_unless HoursRecordNotSubmitted
      authorize_if relates_to_actor_via(:user)
    end

    # Stopping a running session is always allowed (the old Bodyguard rule
    # checked `end_datetime == nil` to bypass lockdown).
    policy [action(:stop), actor_attribute_equals(:role, :employee)] do
      authorize_if relates_to_actor_via(:user)
    end

    policy [action(:stop), AtLeastRole, role: :invoicing] do
      authorize_if relates_to_actor_via(:user)
    end

    # Create: employee can only create sessions for themselves.
    # `relates_to_actor_via` can't filter on creates, so we check the
    # changeset attribute directly via a simple check.
    policy [action_type(:create), actor_attribute_equals(:role, :employee)] do
      forbid_unless HoursRecordNotSubmitted
      authorize_if OwnsResource
    end

    policy [action_type(:create), AtLeastRole, role: :invoicing] do
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

    policy [
      action_type([:update, :destroy]),
      AtLeastRole,
      role: :invoicing
    ] do
      forbid_unless HoursRecordNotSubmitted
      authorize_if relates_to_actor_via(:user)
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
