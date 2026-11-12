# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
defmodule Firmowid.Timetracker.Session do
  @moduledoc """
  A member's work on a project from `start_datetime` to `end_datetime`; a
  session without an end is running.

  Boundaries are stored at minute precision and a session stays within one
  calendar month. A running session is ended after 12 hours by the
  `:auto_stop` trigger. A database trigger and an exclusion constraint reject
  overlapping sessions of a member. Sessions in a month whose hours record was
  submitted are locked (`lockdown`). Scoped by `organization_id` (attribute
  multitenancy).
  """
  use Ash.Resource,
    domain: Firmowid.Timetracker,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource, AshOban],
    fragments: [Firmowid.Timetracker.Session.Persistence]

  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Resource
  alias Firmowid.Timetracker.Changes.ClampSessionBoundaries
  alias Firmowid.Timetracker.Changes.NormalizeSessionBoundaries
  alias Firmowid.Timetracker.Changes.SynchronizeSubmittedMonth
  alias Firmowid.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session.Calculations
  alias Firmowid.Timetracker.Validations.ProjectAccess
  alias Firmowid.Timetracker.Validations.SessionMonthBoundaries

  require Resource

  json_api do
    type "session"
    includes([:project])
    default_fields([:title, :start_datetime, :end_datetime, :is_remote, :lockdown, :project])
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :auto_stop do
        action :auto_stop
        read_action :read_global

        where expr(
                is_nil(end_datetime) and
                  start_datetime <= ago(^ClampSessionBoundaries.max_running_seconds(), :second)
              )

        scheduler_cron "*/5 * * * *"
        default_actor %Firmowid.SystemActor{org_id: nil, role: :session_auto_stopper}
        max_attempts 3
        queue :default

        worker_module_name Firmowid.Timetracker.Session.Worker.AutoStop
        scheduler_module_name Firmowid.Timetracker.Session.Scheduler.AutoStop
      end
    end
  end

  code_interface do
    define :read, action: :read
    define :read_global
    define :list_user_sessions
    define :get_current, not_found_error?: false
    define :current_session, args: [:id]
    define :most_recent
    define :list_overlapping, args: [:member_id, :start_datetime]
    define :start
    define :stop
    define :stop_current
    define :auto_stop
    define :edit_current_user_session
    define :add_completed_sessions, args: [:sessions]
    define :team_presence, args: [:date]
    define :month_duration, args: [:date]
    define :create
    define :update
    define :destroy
  end

  actions do
    defaults [:read]

    # ── Read actions ──────────────────────────────────────────────────

    read :list do
      description """
      Flexible session listing with optional filters.
      started_from is inclusive and started_to is exclusive; omitted bounds
      leave the session start time unrestricted.
      Sorting, loading (duration, lockdown, month_start, week_start), and
      aggregation controlled at callsite.
      """

      argument :member_id, :uuid
      argument :project_id, :uuid
      argument :month, :integer
      argument :year, :integer
      argument :running_only, :boolean
      argument :ids, {:array, :uuid}
      argument :started_from, :utc_datetime
      argument :started_to, :utc_datetime

      prepare build(filter: expr(member_id == ^arg(:member_id))) do
        where present(:member_id)
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

      prepare build(filter: expr(start_datetime >= ^arg(:started_from))) do
        where present(:started_from)
      end

      prepare build(filter: expr(start_datetime < ^arg(:started_to))) do
        where present(:started_to)
      end
    end

    read :read_global do
      description "Every organization's sessions, for the auto-stop trigger."
      multitenancy :allow_global
      pagination keyset?: true, required?: false
    end

    read :list_user_sessions do
      description "List the acting member's sessions, optionally filtered to those starting on or after a date."

      argument :after_date, :date

      pagination offset?: true,
                 keyset?: true,
                 countable: true,
                 default_limit: 25,
                 max_page_size: 100,
                 required?: false

      prepare build(sort: [start_datetime: :desc], load: [:lockdown, :project])
      filter expr(member_id == ^actor([:member, :id]))

      # Ash casts the date to its midnight in UTC.
      prepare build(filter: expr(start_datetime >= ^arg(:after_date))) do
        where present(:after_date)
      end
    end

    read :get_current do
      description "Get the currently running session (no end_datetime) for the acting member."
      get? true

      prepare build(load: [:project])
      filter expr(is_nil(end_datetime))
      filter expr(member_id == ^actor([:member, :id]))
    end

    read :current_session do
      description "Get a session by ID only when it belongs to the acting member."
      get? true

      argument :id, :uuid, allow_nil?: false

      filter expr(id == ^arg(:id))
      filter expr(member_id == ^actor([:member, :id]))
    end

    read :most_recent do
      description "Get the most recent session of the acting member."
      get? true

      prepare build(sort: [start_datetime: :desc], limit: 1)
      filter expr(member_id == ^actor([:member, :id]))
    end

    read :list_overlapping do
      description """
      Find sessions that overlap with a given time range for a member.

      Used for pre-save conflict detection. Mirrors the DB trigger: a missing
      end, of either range, extends it to infinity.
      """

      argument :member_id, :uuid, allow_nil?: false
      argument :start_datetime, :utc_datetime, allow_nil?: false
      argument :end_datetime, :utc_datetime

      prepare build(sort: [start_datetime: :asc], load: [:lockdown])

      filter expr(member_id == ^arg(:member_id))
      filter expr(is_nil(end_datetime) or end_datetime > ^arg(:start_datetime))

      prepare build(filter: expr(start_datetime < ^arg(:end_datetime))) do
        where present(:end_datetime)
      end
    end

    # ── Write actions ─────────────────────────────────────────────────

    create :start do
      description "Start a new time tracking session, stopping the current session if one exists."
      primary? true
      accept [:title, :project_id, :is_remote]

      change set_attribute(:start_datetime, &DateTime.utc_now/0)
      change NormalizeSessionBoundaries
      change set_attribute(:member_id, actor([:member, :id]))
      change SynchronizeSubmittedMonth

      change fn changeset, context ->
        opts = Ash.Scope.to_opts(context)

        Ash.Changeset.before_action(changeset, fn changeset ->
          case stop_current(opts) do
            {:ok, nil} ->
              changeset

            {:ok, stopped} ->
              if DateTime.after?(
                   stopped.end_datetime,
                   Ash.Changeset.get_attribute(changeset, :start_datetime)
                 ) do
                Ash.Changeset.force_change_attribute(
                  changeset,
                  :start_datetime,
                  stopped.end_datetime
                )
              else
                changeset
              end

            {:error, error} ->
              Ash.Changeset.add_error(changeset, error)
          end
        end)
      end
    end

    create :create do
      description "Create a session with explicit attributes (for import or admin use)."
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote, :member_id]
      change NormalizeSessionBoundaries
      change SynchronizeSubmittedMonth
    end

    update :stop do
      description "Stop a running session by setting end_datetime to now."
      accept []
      require_atomic? false

      # A caller's copy may be stale; never move the end of a finished session.
      change filter(expr(is_nil(end_datetime)))
      change set_attribute(:end_datetime, &DateTime.utc_now/0)
      change ClampSessionBoundaries
      change NormalizeSessionBoundaries
    end

    update :auto_stop do
      description """
      End a session left running past the maximum running time, run by the
      `:auto_stop` trigger. The clamp caps it at the maximum running time or the
      end of its start month, whichever comes first.
      """

      accept []
      require_atomic? false

      change set_attribute(:end_datetime, &DateTime.utc_now/0)
      change ClampSessionBoundaries
      change NormalizeSessionBoundaries
    end

    action :stop_current, :struct do
      description """
      Stop the acting member's currently running session, if any.

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

    action :edit_current_user_session, :struct do
      description "Update one of the acting member's unfrozen sessions."
      constraints instance_of: __MODULE__
      argument :id, :uuid, allow_nil?: false
      argument :title, :string
      argument :start_datetime, :utc_datetime
      argument :end_datetime, :utc_datetime
      argument :project_id, :uuid
      argument :is_remote, :boolean

      run &Firmowid.Timetracker.Session.Actions.EditCurrentUser.run/2
    end

    action :add_completed_sessions, {:array, :struct} do
      description """
      Add completed sessions with explicit start and end times for the acting
      member, all or none. Never stops, edits or resumes a running session.
      """

      constraints items: [instance_of: __MODULE__]
      transaction? true

      argument :sessions, {:array, :map} do
        allow_nil? false

        constraints items: [
                      fields: [
                        title: [type: :string, allow_nil?: false],
                        project_id: [type: :uuid, allow_nil?: false],
                        start_datetime: [type: :utc_datetime, allow_nil?: false],
                        end_datetime: [type: :utc_datetime, allow_nil?: false],
                        is_remote: [type: :boolean]
                      ]
                    ]
      end

      run &Firmowid.Timetracker.Session.Actions.AddCompleted.run/2
    end

    action :month_duration, :integer do
      description "Total session seconds in the acting member's month, including the capped running session. Uses the same UTC month and duration as Time tracking."
      argument :date, :date, allow_nil?: false

      run fn input, context ->
        date = input.arguments.date
        opts = Ash.Scope.to_opts(context)

        query =
          Firmowid.Timetracker.query_to_list_sessions(
            %{member_id: context.actor.member.id, month: date.month, year: date.year},
            opts
          )

        with {:ok, %{total: total}} <-
               Ash.aggregate(query, {:total, :sum, field: :duration, default: 0}, opts) do
          {:ok, total}
        end
      end
    end

    action :team_presence, {:array, :map} do
      description """
      Where the organization's active members are on `date`: working now in the
      office or remotely (a running session), on accepted leave covering `date`,
      or neither. Exposes only this state, not sessions or leave reasons.
      """

      constraints items: [
                    fields: [
                      name: [type: :string, allow_nil?: true],
                      status: [
                        type: :atom,
                        allow_nil?: false,
                        constraints: [one_of: [:office, :remote, :leave, :away]]
                      ]
                    ]
                  ]

      argument :date, :date, allow_nil?: false

      run &Firmowid.Timetracker.Session.Actions.TeamPresence.run/2
    end

    update :update do
      description "Update session attributes."
      primary? true
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote]
      require_atomic? false

      change NormalizeSessionBoundaries
      change SynchronizeSubmittedMonth
    end

    destroy :destroy do
      description "Delete a session."
      primary? true
      require_atomic? false
      change SynchronizeSubmittedMonth
    end
  end

  policies do
    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:list, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    bypass {SystemActorRole, roles: [:session_auto_stopper]} do
      authorize_if action([:read_global, :auto_stop])
    end

    # Pinned salaries are split between the projects the employee logged time on.
    bypass [{SystemActorRole, roles: [:analysis_reader]}, action(:list)] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    # Who works now, for the team presence every member sees.
    bypass [{SystemActorRole, roles: [:presence_reader]}, action(:list)] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    policy Firmowid.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action(:read_global) do
      forbid_if always()
    end

    policy action_type(:read) do
      description "Human superusers can read all sessions within the tenant; other users can read their own."
      authorize_if actor_attribute_equals(:system_role, :superuser)
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action_type(:create) do
      forbid_unless HoursRecordNotSubmitted
      authorize_if Firmowid.Checks.CreatingForActorMember
    end

    policy action_type([:update, :destroy]) do
      forbid_unless HoursRecordNotSubmitted
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action(:stop_current) do
      authorize_if actor_present()
    end

    policy action(:edit_current_user_session) do
      authorize_if actor_present()
    end

    policy action(:add_completed_sessions) do
      authorize_if actor_present()
    end

    policy action(:team_presence) do
      authorize_if {AtLeastRole, role: :employee}
    end

    policy action(:month_duration) do
      authorize_if {AtLeastRole, role: :employee}
    end
  end

  preparations do
    prepare build(load: [:duration])
  end

  validations do
    validate compare(:start_datetime, less_than_or_equal_to: :end_datetime),
      on: [:create, :update],
      where: [present(:end_datetime)],
      message: "must be before end datetime"

    validate {SessionMonthBoundaries, []}, on: [:create, :update]

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
    belongs_to :member, Firmowid.Core.Member do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :project, Project do
      public? true
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    # Ash expressions have no EXTRACT function, hence the fragments.
    has_many :hours_records, HoursRecord do
      no_attributes? true

      description "HoursRecords matching this session's member, month, year, and org — used for lockdown checks."

      filter expr(
               submission_status == :submitted and member_id == parent(member_id) and
                 organization_id == parent(organization_id) and
                 month == fragment("EXTRACT(MONTH FROM ?)::integer", parent(start_datetime)) and
                 year == fragment("EXTRACT(YEAR FROM ?)::integer", parent(start_datetime))
             )
    end
  end

  calculations do
    calculate :duration, :integer, Calculations.Duration do
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

    calculate :lockdown, :boolean, expr(exists(hours_records, true)) do
      public? true

      description "Whether an hours record has been submitted for this session's month, locking edits."
    end
  end

  identities do
    identity :current_session, [:id, :member_id]
  end
end
