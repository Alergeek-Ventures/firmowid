defmodule Firmowid.Ash.Timetracker.Session do
  @moduledoc """
  Ash resource wrapping the existing `sessions` table.

  Attribute multitenancy via `organization_id`. Write actions include `start`
  (begins a new session), `stop` (ends a running session), `stop_current`
  (ends the actor's running session without a client-supplied id), `create`
  (full attrs), `update`, and `destroy`. Overlap is enforced by a DB trigger —
  the resulting Postgrex error is surfaced as-is by AshPostgres.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Changes.NormalizeSessionBoundaries
  alias Firmowid.Ash.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Ash.Timetracker.Project
  alias Firmowid.Ash.Timetracker.Validations.DatetimeOrder
  alias Firmowid.Ash.Timetracker.Validations.ProjectAccess

  require Ash.Query
  require Resource

  postgres do
    table "sessions"
    repo Firmowid.Repo

    custom_statements do
      statement :normalize_session_boundaries_to_minutes do
        up """
        DO $$
        BEGIN
          ALTER TABLE sessions DISABLE TRIGGER no_session_overlap_trigger;

          UPDATE sessions
          SET
            start_datetime = date_trunc('minute', start_datetime),
            end_datetime = date_trunc('minute', end_datetime)
          WHERE
            start_datetime IS DISTINCT FROM date_trunc('minute', start_datetime)
            OR end_datetime IS DISTINCT FROM date_trunc('minute', end_datetime);

          ALTER TABLE sessions ENABLE TRIGGER no_session_overlap_trigger;
        END $$;
        """

        down "SELECT 1;"
      end
    end
  end

  code_interface do
    define :read, action: :read
    define :list_user_sessions
    define :get_current, not_found_error?: false
    define :most_recent
    define :list_overlapping, args: [:user_id, :start_datetime]
    define :start
    define :stop
    define :stop_current
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

      argument :after_date, :date

      prepare build(sort: [start_datetime: :desc], load: [:lockdown])
      filter expr(user_id == ^actor(:id))

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

      filter expr(is_nil(end_datetime))
      filter expr(user_id == ^actor(:id))
    end

    read :most_recent do
      description "Get the most recent session for a user."
      get? true

      prepare build(sort: [start_datetime: :desc], limit: 1)
      filter expr(user_id == ^actor(:id))
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

      prepare build(sort: [start_datetime: :asc], load: [:lockdown])

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
      primary? true
      accept [:title, :project_id, :is_remote]

      change set_attribute(:start_datetime, &DateTime.utc_now/0)
      change NormalizeSessionBoundaries
      change relate_actor(:user)
    end

    create :create do
      description "Create a session with explicit attributes (for import or admin use)."
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote, :user_id]
      change NormalizeSessionBoundaries
    end

    update :stop do
      description "Stop a running session by setting end_datetime to now."
      accept []
      require_atomic? false

      change set_attribute(:end_datetime, &DateTime.utc_now/0)
      change NormalizeSessionBoundaries
    end

    action :stop_current, :struct do
      description """
      Stop the acting user's currently running session, if any.

      Used by MCP so clients never supply a session id. Returns nil when
      there is no active session.
      """

      constraints instance_of: __MODULE__
      allow_nil? true

      run fn _input, context ->
        opts = Ash.Context.to_opts(context)

        case get_current(opts) do
          {:ok, nil} ->
            {:ok, nil}

          {:ok, session} ->
            stop(session, opts)

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    update :update do
      description "Update session attributes."
      primary? true
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote]
      require_atomic? false

      change NormalizeSessionBoundaries
    end
  end

  policies do
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      forbid_unless HoursRecordNotSubmitted
      authorize_if relating_to_actor(:user)
    end

    policy action_type([:update, :destroy]) do
      forbid_unless HoursRecordNotSubmitted
      authorize_if relates_to_actor_via(:user)
    end

    policy action(:stop_current) do
      authorize_if actor_present()
    end
  end

  preparations do
    prepare build(load: [:duration])
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
