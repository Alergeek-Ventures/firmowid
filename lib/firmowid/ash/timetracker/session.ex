# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
defmodule Firmowid.Ash.Timetracker.Session do
  @moduledoc """
  Ash resource wrapping the existing `sessions` table.

  Attribute multitenancy via `organization_id`. Write actions include `start`
  (begins a new session), `stop` (ends a running session), `stop_current`
  (ends the actor's running session without a client-supplied id), `create`
  (full attrs), `update`, and `destroy`. A DB trigger rejects overlapping sessions;
  an exclusion constraint also protects concurrent writes. Database errors are
  surfaced by AshPostgres.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Changes.ClampSessionBoundaries
  alias Firmowid.Ash.Timetracker.Changes.NormalizeSessionBoundaries
  alias Firmowid.Ash.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Ash.Timetracker.Project
  alias Firmowid.Ash.Timetracker.Session.Calculations
  alias Firmowid.Ash.Timetracker.Session.Overlap
  alias Firmowid.Ash.Timetracker.Validations.DatetimeOrder
  alias Firmowid.Ash.Timetracker.Validations.ProjectAccess
  alias Firmowid.Ash.Timetracker.Validations.SessionMonthBoundaries
  alias Firmowid.Ash.Timetracker.Workers.StopSessionWorker

  require Logger
  require Resource

  postgres do
    table "sessions"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
    end

    custom_indexes do
      index [:member_id]
    end

    custom_statements do
      # Legacy sessions from 2025-02 to 2025-07 had 24 overlapping pairs and one
      # reversed range. Shift them apart and fold the reversed range into the
      # same member's multi-day session, keeping every member's monthly sum of
      # session seconds, which submitted hours records and payroll rely on.
      statement :repair_legacy_session_overlaps do
        up """
        DO $$
        DECLARE
          changed integer;
        BEGIN
          CREATE TEMP TABLE session_sums_before ON COMMIT DROP AS
          SELECT member_id, date_trunc('month', start_datetime) AS month,
                 sum(extract(epoch FROM end_datetime - start_datetime)) AS seconds
          FROM sessions GROUP BY 1, 2;

          ALTER TABLE sessions DISABLE TRIGGER no_session_overlap_trigger;

          DELETE FROM sessions
          WHERE id = '01961c41-4f83-7077-9d12-cf43165ce9eb'
            AND start_datetime = TIMESTAMP '2025-03-11 07:32:00'
            AND end_datetime = TIMESTAMP '2025-03-10 16:03:00';

          UPDATE sessions s
          SET start_datetime = v.new_start, end_datetime = v.new_end
          FROM (VALUES
            ('019686b6-6cad-7b80-829b-90a12a710858'::uuid, TIMESTAMP '2025-04-30 12:40:24', TIMESTAMP '2025-04-30 15:14:55', TIMESTAMP '2025-04-30 14:00:00', TIMESTAMP '2025-04-30 16:34:31'),
            ('0196af86-e05a-7781-b166-bbe1e7a122dc', '2025-05-08 10:52:00', '2025-05-08 13:00:00', '2025-05-08 10:52:44', '2025-05-08 13:00:44'),
            ('019720a5-27c3-7e8d-a2ac-5b3da4386e04', '2025-05-30 10:03:03', '2025-05-30 10:20:54', '2025-05-30 13:00:00', '2025-05-30 13:17:51'),
            ('019720eb-9eda-76fe-9fb1-4dcbef45968e', '2025-05-30 11:20:01', '2025-05-30 14:36:02', '2025-05-30 13:17:51', '2025-05-30 16:33:52'),
            ('0197cbad-a1f5-7b53-9e9f-30a5ad69d3d4', '2025-07-02 15:07:00', '2025-07-02 16:32:00', '2025-07-02 15:07:11', '2025-07-02 16:32:11'),
            ('0197ea8a-32f0-7203-8e17-ca791e1e78ab', '2025-07-08 14:56:00', '2025-07-08 16:30:00', '2025-07-08 14:56:04', '2025-07-08 16:30:04'),
            ('0196ab9d-013e-711a-b22c-57111ff5fc9d', '2025-05-05 09:00:00', '2025-05-05 15:40:00', '2025-05-05 09:10:00', '2025-05-05 15:50:00'),
            ('0195ff94-f792-7d3b-9d1d-1559b750811e', '2025-03-24 09:00:00', '2025-03-24 10:30:00', '2025-03-24 12:00:00', '2025-03-24 13:30:00'),
            ('0196ce7f-189e-7a3b-b74f-c70f2ec19558', '2025-04-30 04:00:00', '2025-04-30 11:00:00', '2025-04-29 23:00:00', '2025-04-30 06:00:00'),
            ('01961c3e-adfe-7688-904b-38041b1eed9b', '2025-03-05 09:29:00', '2025-03-08 17:02:00', '2025-03-05 09:29:00', '2025-03-08 01:33:00'),
            ('01961c3f-5a55-730b-8014-0630f8edc3ab', '2025-03-06 08:30:00', '2025-03-06 17:30:00', '2025-03-08 01:33:00', '2025-03-08 10:33:00'),
            ('01961c3f-ed73-7c87-8ea5-0644e22c30e6', '2025-03-07 07:30:00', '2025-03-07 14:09:00', '2025-03-08 10:33:00', '2025-03-08 17:12:00'),
            ('01957678-1fd7-7ac2-9508-4f317362b7fa', '2025-03-08 13:55:00', '2025-03-08 15:45:00', '2025-03-08 17:12:00', '2025-03-08 19:02:00'),
            ('01978878-ab23-7e4e-a851-b1afbb5ca140', '2025-06-10 13:54:00', '2025-06-10 18:55:00', '2025-06-10 18:55:00', '2025-06-10 23:56:00'),
            ('01978876-d40b-79d9-b323-387d9ebc602e', '2025-06-12 06:52:00', '2025-06-12 18:55:00', '2025-06-12 18:55:00', '2025-06-13 06:58:00'),
            ('0194fa66-b8e5-71dd-85a7-7033c2e88276', '2025-02-12 13:43:00', '2025-02-12 15:53:00', '2025-02-12 13:43:37', '2025-02-12 15:53:37'),
            ('01951d3c-5609-709c-a17d-07fa69d26025', '2025-02-19 08:00:00', '2025-02-19 08:12:22', '2025-02-19 08:00:10', '2025-02-19 08:12:32'),
            ('01951d43-f589-7a12-ae76-20b2f4fedd39', '2025-02-19 08:12:27', '2025-02-19 08:47:55', '2025-02-19 08:12:32', '2025-02-19 08:48:00'),
            ('019527e8-26be-7bb4-b85c-22d723a0044a', '2025-02-21 09:44:00', '2025-02-21 12:29:00', '2025-02-21 09:44:50', '2025-02-21 12:29:50'),
            ('01952a4c-9d72-71ba-bb03-0c677e2e5536', '2025-02-21 20:56:00', '2025-02-21 23:19:00', '2025-02-21 20:56:51', '2025-02-21 23:19:51'),
            ('01953786-0ec8-74bd-b15c-53c78413f90f', '2025-02-24 10:34:00', '2025-02-24 14:12:45', '2025-02-24 10:34:40', '2025-02-24 14:13:25'),
            ('0195474b-1747-78a5-a071-4135ea31545e', '2025-02-27 11:50:00', '2025-02-27 13:40:00', '2025-02-27 12:03:56', '2025-02-27 13:53:56'),
            ('0195894a-c9d6-770f-86f1-4d854df20d13', '2025-03-12 07:38:00', '2025-03-12 14:25:00', '2025-03-12 07:38:41', '2025-03-12 14:25:41'),
            ('0195c03a-532a-74b8-89c7-8952a4e33e6c', '2025-03-21 11:00:00', '2025-03-21 14:00:00', '2025-03-21 12:30:00', '2025-03-21 15:30:00'),
            ('0195d26f-211c-7a19-a61d-61238373abd0', '2025-03-26 12:25:00', '2025-03-26 14:02:57', '2025-03-26 12:30:40', '2025-03-26 14:08:37'),
            ('0195d2d8-0568-781f-b977-7abf35a4fcd4', '2025-03-26 14:00:00', '2025-03-26 14:39:45', '2025-03-26 14:08:37', '2025-03-26 14:48:22')
          ) AS v(id, old_start, old_end, new_start, new_end)
          WHERE s.id = v.id AND s.start_datetime = v.old_start AND s.end_datetime = v.old_end;
          GET DIAGNOSTICS changed = ROW_COUNT;

          ALTER TABLE sessions ENABLE TRIGGER no_session_overlap_trigger;

          IF changed NOT IN (0, 26) THEN
            RAISE EXCEPTION 'Expected 0 or 26 legacy sessions to repair, found %', changed;
          END IF;

          IF EXISTS (SELECT 1 FROM sessions WHERE end_datetime < start_datetime) THEN
            RAISE EXCEPTION 'A session with a reversed range remains';
          END IF;

          IF EXISTS (
            SELECT 1 FROM sessions a
            JOIN sessions b ON a.member_id = b.member_id AND a.id < b.id
            WHERE tsrange(a.start_datetime, a.end_datetime, '[)') && tsrange(b.start_datetime, b.end_datetime, '[)')
          ) THEN
            RAISE EXCEPTION 'Overlapping sessions remain';
          END IF;

          IF EXISTS (
            SELECT 1 FROM session_sums_before b
            FULL JOIN (
              SELECT member_id, date_trunc('month', start_datetime) AS month,
                     sum(extract(epoch FROM end_datetime - start_datetime)) AS seconds
              FROM sessions GROUP BY 1, 2
            ) a USING (member_id, month)
            WHERE a.seconds IS DISTINCT FROM b.seconds
          ) THEN
            RAISE EXCEPTION 'Legacy session repair changed a monthly session sum';
          END IF;
        END $$;
        """

        down "SELECT 1;"
      end

      # Legacy sessions stay outside the exclusion constraint: rebuilding it in
      # the repair transaction fails on the deleted reversed row version.
      statement :exclude_overlapping_member_sessions do
        up """
        ALTER TABLE sessions
        ADD CONSTRAINT no_overlapping_member_sessions
        EXCLUDE USING gist (
          member_id WITH =,
          tsrange(start_datetime, end_datetime, '[)') WITH &&
        )
        WHERE (inserted_at >= TIMESTAMP '2025-07-09 00:00:00');
        """

        down """
        ALTER TABLE sessions DROP CONSTRAINT no_overlapping_member_sessions;
        """
      end

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
            start_datetime >= TIMESTAMPTZ '2026-08-01 00:00:00Z'
            AND start_datetime < TIMESTAMPTZ '2026-09-01 00:00:00Z'
            AND (
              start_datetime IS DISTINCT FROM date_trunc('minute', start_datetime)
              OR end_datetime IS DISTINCT FROM date_trunc('minute', end_datetime)
            );

          ALTER TABLE sessions ENABLE TRIGGER no_session_overlap_trigger;
        END $$;
        """

        down "SELECT 1;"
      end

      statement :prevent_member_session_overlap do
        up """
        CREATE OR REPLACE FUNCTION prevent_session_overlap()
        RETURNS TRIGGER AS $$
        DECLARE
          new_start timestamp := NEW.start_datetime;
          new_end timestamp := NEW.end_datetime;
        BEGIN
          IF EXISTS (
            SELECT 1 FROM sessions
            WHERE member_id = NEW.member_id
              AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000')
              AND (
                start_datetime < COALESCE(new_end, 'infinity') AND COALESCE(end_datetime, 'infinity') > new_start
              )
          ) THEN
            RAISE EXCEPTION 'Session for this member overlaps with an existing session.';
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """

        down """
        CREATE OR REPLACE FUNCTION prevent_session_overlap()
        RETURNS TRIGGER AS $$
        DECLARE
          new_start timestamp := NEW.start_datetime;
          new_end timestamp := NEW.end_datetime;
        BEGIN
          IF EXISTS (
            SELECT 1 FROM sessions
            WHERE user_id = NEW.user_id
              AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000')
              AND (
                start_datetime < COALESCE(new_end, 'infinity') AND COALESCE(end_datetime, 'infinity') > new_start
              )
          ) THEN
            RAISE EXCEPTION 'Session for this user overlaps with an existing session.';
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
      end
    end
  end

  code_interface do
    define :read, action: :read
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

    read :list_user_sessions do
      description "List the acting member's sessions, optionally filtered to those starting on or after a date."

      argument :after_date, :date

      pagination offset?: true,
                 countable: true,
                 default_limit: 25,
                 max_page_size: 100,
                 required?: false

      prepare build(sort: [start_datetime: :desc], load: [:lockdown, :project])
      filter expr(member_id == ^actor([:member, :id]))

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

      Used for pre-save conflict detection. See `Session.Overlap.filter/3` for the
      overlap predicate that mirrors the DB trigger.
      """

      argument :member_id, :uuid, allow_nil?: false
      argument :start_datetime, :utc_datetime, allow_nil?: false
      argument :end_datetime, :utc_datetime
      argument :exclude_id, :uuid

      prepare build(sort: [start_datetime: :asc], load: [:lockdown])

      filter expr(member_id == ^arg(:member_id))

      prepare fn query, _context ->
        exclude_id = Ash.Query.get_argument(query, :exclude_id)
        new_end = Ash.Query.get_argument(query, :end_datetime)

        query
        |> Overlap.maybe_exclude_id(exclude_id)
        |> Overlap.filter(Ash.Query.get_argument(query, :start_datetime), new_end)
      end
    end

    # ── Write actions ─────────────────────────────────────────────────

    create :start do
      description "Start a new time tracking session (auto-sets start_datetime to now)."
      primary? true
      accept [:title, :project_id, :is_remote]

      change set_attribute(:start_datetime, &DateTime.utc_now/0)
      change NormalizeSessionBoundaries
      change set_attribute(:member_id, actor([:member, :id]))

      change after_action(fn _changeset, session, _context ->
               case StopSessionWorker.enqueue(session) do
                 {:ok, _job} ->
                   Logger.info("Enqueued session auto-stop session_id=#{session.id} org=#{session.organization_id}")

                   {:ok, session}

                 {:error, reason} ->
                   Logger.error("Failed to enqueue session auto-stop session_id=#{session.id} reason=#{inspect(reason)}")

                   {:ok, session}
               end
             end)
    end

    create :create do
      description "Create a session with explicit attributes (for import or admin use)."
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote, :member_id]
      change NormalizeSessionBoundaries
    end

    update :stop do
      description "Stop a running session by setting end_datetime to now."
      accept []
      require_atomic? false

      change set_attribute(:end_datetime, &DateTime.utc_now/0)
      change ClampSessionBoundaries
      change NormalizeSessionBoundaries

      change after_action(fn _changeset, session, _context ->
               StopSessionWorker.cancel(session.id)
               {:ok, session}
             end)
    end

    update :auto_stop do
      description """
      Cap a forgotten running session at start_datetime + 12 hours.

      Used by StopSessionWorker. Does not accept client input. The result is
      additionally clamped to the end of the start month, so a session left
      running across a month boundary still lands wholly in one month.
      """

      accept []
      require_atomic? false

      change fn changeset, _context ->
        start_datetime = Ash.Changeset.get_attribute(changeset, :start_datetime)

        Ash.Changeset.force_change_attribute(
          changeset,
          :end_datetime,
          DateTime.shift(start_datetime, second: StopSessionWorker.max_running_seconds())
        )
      end

      change ClampSessionBoundaries
      change NormalizeSessionBoundaries

      change after_action(fn _changeset, session, _context ->
               StopSessionWorker.cancel(session.id)
               {:ok, session}
             end)
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

      run &Firmowid.Ash.Timetracker.Session.Actions.EditCurrentUser.run/2
    end

    update :update do
      description "Update session attributes."
      primary? true
      accept [:title, :start_datetime, :end_datetime, :project_id, :is_remote]
      require_atomic? false

      change NormalizeSessionBoundaries

      change after_action(fn _changeset, session, _context ->
               if session.end_datetime do
                 StopSessionWorker.cancel(session.id)
               end

               {:ok, session}
             end)
    end

    destroy :destroy do
      description "Delete a session and cancel auto-stop worker."
      primary? true
      require_atomic? false

      change after_action(fn _changeset, session, _context ->
               StopSessionWorker.cancel(session.id)
               {:ok, session}
             end)
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
      authorize_if action_type(:read)
      authorize_if action(:auto_stop)
    end

    # Pinned salaries are split between the projects the employee logged time on.
    bypass [{SystemActorRole, roles: [:analysis_reader]}, action(:list)] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      description "Human superusers can read all sessions within the tenant; other users can read their own."
      authorize_if actor_attribute_equals(:system_role, :superuser)
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action_type(:create) do
      forbid_unless HoursRecordNotSubmitted
      authorize_if Firmowid.Ash.Checks.CreatingForActorMember
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
  end

  preparations do
    prepare build(load: [:duration])
  end

  validations do
    validate {DatetimeOrder, start_field: :start_datetime, end_field: :end_datetime},
      on: [:create, :update]

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
    belongs_to :member, Firmowid.Ash.Core.Member do
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

    calculate :month_start, :naive_datetime, Calculations.MonthStart do
      description "First day of the month this session belongs to (truncated start_datetime)."
    end

    calculate :week_start, :naive_datetime, Calculations.WeekStart do
      description "Monday of the week this session belongs to (ISO week, truncated start_datetime)."
    end

    calculate :lockdown, :boolean, Calculations.Lockdown do
      public? true

      description "Whether an hours record has been submitted for this session's month, locking edits."
    end
  end

  identities do
    identity :current_session, [:id, :member_id]
  end
end
