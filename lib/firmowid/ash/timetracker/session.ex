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
  alias Firmowid.Ash.Timetracker.Validations.DatetimeOrder
  alias Firmowid.Ash.Timetracker.Validations.ProjectAccess
  alias Firmowid.Helpers.TimeConverter

  require Resource

  postgres do
    table("sessions")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute(:title, :string, public?: true, allow_nil?: false)
    attribute(:start_datetime, :utc_datetime, public?: true, allow_nil?: false)
    attribute(:end_datetime, :utc_datetime, public?: true)
    attribute(:is_remote, :boolean, public?: true, default: false)

    Resource.firmowid_timestamps()
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
      public?(true)
    end

    calculate :lockdown,
              :boolean,
              expr(
                fragment(
                  "EXISTS (SELECT 1 FROM hours_records hr WHERE hr.user_id = ? AND hr.month = EXTRACT(MONTH FROM ?)::integer AND hr.year = EXTRACT(YEAR FROM ?)::integer AND hr.organization_id = ?)",
                  user_id,
                  start_datetime,
                  start_datetime,
                  organization_id
                )
              ) do
      public?(true)
      description("Whether an hours record has been submitted for this session's month, locking edits.")
    end
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :project, Firmowid.Ash.Timetracker.Project do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(false)
    end
  end

  validations do
    validate({DatetimeOrder, start_field: :start_datetime, end_field: :end_datetime},
      on: [:create, :update]
    )

    validate({ProjectAccess, []},
      on: [:create, :update],
      where: [changing(:project_id)]
    )
  end

  actions do
    defaults([:read, :destroy])

    # ── Read actions ──────────────────────────────────────────────────

    read :list_user_sessions do
      description("List a user's sessions, optionally filtered to those starting on or after a date.")

      argument(:user_id, :uuid, allow_nil?: false)
      argument(:after_date, :date)

      prepare(build(sort: [start_datetime: :desc], load: [:duration, :lockdown]))

      filter(expr(user_id == ^arg(:user_id)))

      prepare(fn query, _context ->
        case Ash.Query.get_argument(query, :after_date) do
          nil ->
            query

          date ->
            dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
            Ash.Query.do_filter(query, start_datetime: [greater_than_or_equal: dt])
        end
      end)
    end

    read :get_current do
      description("Get the currently running session (no end_datetime) for the acting user.")
      get?(true)

      prepare(build(sort: [start_datetime: :desc], limit: 1, load: [:duration]))

      filter(expr(is_nil(end_datetime)))

      prepare(fn query, context ->
        case context.actor do
          %{id: actor_id} -> Ash.Query.do_filter(query, user_id: actor_id)
          _ -> query
        end
      end)
    end

    read :most_recent do
      description("Get the most recent session for a user.")
      get?(true)

      argument(:user_id, :uuid, allow_nil?: false)

      prepare(build(sort: [start_datetime: :desc], limit: 1))

      filter(expr(user_id == ^arg(:user_id)))
    end

    read :by_ids do
      description("Fetch sessions by a list of IDs.")

      argument(:ids, {:array, :uuid}, allow_nil?: false)

      prepare(build(load: [:duration]))

      filter(expr(id in ^arg(:ids)))
    end

    # ── Write actions ─────────────────────────────────────────────────

    create :start do
      description("Start a new time tracking session (auto-sets start_datetime to now).")
      accept([:title, :project_id, :is_remote])

      change(set_attribute(:start_datetime, &DateTime.utc_now/0))
      change(relate_actor(:user))
    end

    create :create do
      description("Create a session with explicit attributes (for import or admin use).")
      accept([:title, :start_datetime, :end_datetime, :project_id, :is_remote, :user_id])
    end

    update :stop do
      description("Stop a running session by setting end_datetime to now.")
      accept([])
      require_atomic?(false)

      change(set_attribute(:end_datetime, &DateTime.utc_now/0))
    end

    update :update do
      description("Update session attributes.")
      accept([:title, :start_datetime, :end_datetime, :project_id, :is_remote])
      require_atomic?(false)
    end

    # ── Generic actions (non-standard return shapes) ──────────────────

    action :weeks_with_sessions, {:array, :date} do
      description("Distinct weeks (as Monday dates) that have sessions for a user.")

      argument(:user_id, :uuid, allow_nil?: false)
      argument(:after_date, :date)
      argument(:limit, :integer)
      argument(:timezone, :string, default: "Etc/UTC")

      run(fn input, _context ->
        import Ecto.Query

        user_id = input.arguments.user_id
        after_date = input.arguments[:after_date]
        limit = input.arguments[:limit]
        timezone = input.arguments[:timezone] || "Etc/UTC"

        query =
          Session
          |> where([s], s.user_id == ^user_id)
          |> select([s], fragment("date_trunc('week', ?)", s.start_datetime))
          |> distinct(true)
          |> order_by([s], desc: fragment("date_trunc('week', ?)", s.start_datetime))

        query =
          if after_date do
            dt = DateTime.new!(after_date, ~T[00:00:00])
            where(query, [s], s.start_datetime < ^dt)
          else
            query
          end

        query = if limit, do: limit(query, ^limit), else: query

        dates =
          query
          |> Firmowid.Repo.all()
          |> Enum.map(fn date ->
            date
            |> DateTime.from_naive!("Etc/UTC")
            |> DateTime.shift_zone!(timezone)
            |> DateTime.to_date()
          end)

        {:ok, dates}
      end)
    end

    action :grouped_user_project_sessions, {:array, :map} do
      description("Sessions grouped by title for a user+project+month/year, returning title + sum duration (seconds).")

      argument(:user_id, :uuid, allow_nil?: false)
      argument(:project_id, :uuid, allow_nil?: false)
      argument(:month, :integer, allow_nil?: false)
      argument(:year, :integer, allow_nil?: false)

      run(fn input, _context ->
        import Ecto.Query

        %{user_id: user_id, project_id: project_id, month: month, year: year} = input.arguments

        results =
          Firmowid.Repo.all(
            from s in Session,
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

        {:ok, results}
      end)
    end

    action :months_with_sessions, {:array, :naive_datetime} do
      description("Distinct months (as date_trunc values) that have sessions. Optionally filtered by user or project.")

      argument(:user_id, :uuid)
      argument(:project_id, :uuid)

      run(fn input, _context ->
        import Ecto.Query

        query =
          Session
          |> select([s], "date_trunc('month', ?)" |> fragment(s.start_datetime) |> selected_as(:date))
          |> distinct([s], selected_as(:date))
          |> order_by([s], desc: selected_as(:date))

        query =
          case input.arguments[:user_id] do
            nil -> query
            uid -> where(query, [s], s.user_id == ^uid)
          end

        query =
          case input.arguments[:project_id] do
            nil -> query
            pid -> where(query, [s], s.project_id == ^pid)
          end

        {:ok, Firmowid.Repo.all(query)}
      end)
    end

    action :total_time_worked, :integer do
      description("Sum of session durations (seconds) for a month/year, optionally filtered by user and/or project.")

      argument(:month, :integer, allow_nil?: false)
      argument(:year, :integer, allow_nil?: false)
      argument(:user_id, :uuid)
      argument(:project_id, :uuid)

      run(fn input, _context ->
        import Ecto.Query

        %{month: month, year: year} = input.arguments

        query =
          from s in Session,
            where:
              fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
                fragment("extract(year from ?) = ?", s.start_datetime, ^year),
            limit: 1,
            select:
              "extract(epoch from coalesce(?, now()) - ?)"
              |> fragment(s.end_datetime, s.start_datetime)
              |> sum()
              |> coalesce(0)
              |> type(:integer)
              |> selected_as(:time_worked)

        query =
          case input.arguments[:user_id] do
            nil -> query
            uid -> where(query, [s], s.user_id == ^uid)
          end

        query =
          case input.arguments[:project_id] do
            nil -> query
            pid -> where(query, [s], s.project_id == ^pid)
          end

        {:ok, Firmowid.Repo.one(query) || 0}
      end)
    end

    action :most_demanding_project, :map do
      description("The project with the most time worked in a given month/year.")

      argument(:month, :integer, allow_nil?: false)
      argument(:year, :integer, allow_nil?: false)

      run(fn input, _context ->
        import Ecto.Query

        %{month: month, year: year} = input.arguments

        result =
          Firmowid.Repo.one(
            from s in Session,
              join: p in Firmowid.Timetracker.Project,
              on: s.project_id == p.id,
              where:
                fragment("extract(month from ?) = ?", s.start_datetime, ^month) and
                  fragment("extract(year from ?) = ?", s.start_datetime, ^year),
              group_by: p.id,
              order_by: [desc: selected_as(:time_worked)],
              limit: 1,
              select: %{
                project: p,
                time_worked:
                  "extract(epoch from coalesce(?, now()) - ?)"
                  |> fragment(s.end_datetime, s.start_datetime)
                  |> sum()
                  |> type(:integer)
                  |> selected_as(:time_worked)
              }
          )

        {:ok, result}
      end)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if(always())
    end

    policy [action_type(:read), actor_attribute_equals(:role, :employee)] do
      authorize_if(relates_to_actor_via(:user))
    end

    policy [action_type([:create, :update, :destroy]), actor_attribute_equals(:role, :employee)] do
      authorize_if(relates_to_actor_via(:user))
    end

    policy [action_type(:action), actor_attribute_equals(:role, :employee)] do
      authorize_if(always())
    end
  end
end
