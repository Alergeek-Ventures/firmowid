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

  require Resource

  postgres do
    table("projects")
    repo(Firmowid.Repo)
    migrate?(false)
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

    has_many :sessions, Firmowid.Ash.Timetracker.Session
    has_many :project_users, ProjectUser

    many_to_many :users, Firmowid.Ash.Core.User do
      through(ProjectUser)
      source_attribute_on_join_resource(:project_id)
      destination_attribute_on_join_resource(:user_id)
    end
  end

  actions do
    defaults([:read])

    # ── Read actions ──────────────────────────────────────────────────

    read :get do
      description("Get a single project by ID with users and counterparty preloaded.")
      get?(true)

      prepare(build(load: [:users, :counterparty]))
    end

    read :by_ids do
      description("Fetch projects by a list of IDs.")

      argument(:ids, {:array, :uuid}, allow_nil?: false)

      filter(expr(id in ^arg(:ids)))
    end

    read :with_users do
      description("All projects preloaded with their users.")

      prepare(build(load: [:users]))
    end

    read :for_user do
      description("Projects that a specific user belongs to (via project_users join).")

      argument(:user_id, :uuid, allow_nil?: false)

      filter(expr(exists(project_users, user_id == ^arg(:user_id))))
    end

    read :active_for_user do
      description("Active (non-archived) projects for a specific user, ordered by name.")

      argument(:user_id, :uuid, allow_nil?: false)

      filter(expr(is_nil(archived_at) and exists(project_users, user_id == ^arg(:user_id))))

      prepare(build(sort: [name: :asc]))
    end

    # ── List actions with duration aggregation ─────────────────────────

    action :active, {:array, :map} do
      description("Active projects with monthly session duration (hours). Supports optional ParadeDB search.")

      argument(:date, :date, allow_nil?: false)
      argument(:search, :string)

      run(fn input, _context ->
        list_projects_with_duration(
          _archived? = false,
          _all_time? = false,
          input.arguments.date,
          input.arguments[:search]
        )
      end)
    end

    action :archived, {:array, :map} do
      description("Archived projects with monthly session duration (hours). Supports optional ParadeDB search.")

      argument(:date, :date, allow_nil?: false)
      argument(:search, :string)

      run(fn input, _context ->
        list_projects_with_duration(
          _archived? = true,
          _all_time? = false,
          input.arguments.date,
          input.arguments[:search]
        )
      end)
    end

    action :archived_total, {:array, :map} do
      description("Archived projects with all-time session duration (hours). Supports optional ParadeDB search.")

      argument(:search, :string)

      run(fn input, _context ->
        list_projects_with_duration(
          _archived? = true,
          _all_time? = true,
          nil,
          input.arguments[:search]
        )
      end)
    end

    # ── Write actions ─────────────────────────────────────────────────

    create :create do
      description("Create a project with automatic TagDefinition creation for analysis tagging.")

      accept([:name, :counterparty_id])
      change(CreateProjectTag)
    end

    update :update do
      description("Update project attributes and sync the associated tag definition name.")
      accept([:name, :counterparty_id])
      require_atomic?(false)
      change(SyncProjectTagName)
    end

    update :archive do
      description("Archive a project by setting archived_at to today.")
      accept([])
      require_atomic?(false)

      change(set_attribute(:archived_at, &Date.utc_today/0))
    end

    update :unarchive do
      description("Unarchive a project by clearing archived_at.")
      accept([])

      change(set_attribute(:archived_at, nil))
    end

    destroy :destroy do
      description("Delete a project and clean up its orphaned tag definition.")
      require_atomic?(false)
      change(CleanupProjectTag)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type(:action) do
      authorize_if(always())
    end
  end

  # ── Private helpers for duration-aggregated listings ──────────────────
  #
  # These use the old Ecto schema modules (Firmowid.Timetracker.Project/Session)
  # for `from()` queries because they carry column type metadata needed by
  # Postgrex (especially for UUID columns). The Ash resources ARE Ecto schemas
  # too, but referencing `__MODULE__` inside its own generic action closures
  # would create confusing self-references. The old schemas point to the same
  # underlying tables and will be removed once callers are fully migrated.

  defp list_projects_with_duration(archived?, all_time?, date, search) do
    import Ecto.Query

    alias Firmowid.Timetracker.Project, as: OldProject
    alias Firmowid.Timetracker.Session, as: OldSession

    duration_subquery = build_duration_subquery(OldSession, all_time?, date)

    query =
      from(p in OldProject,
        left_join: sd in subquery(duration_subquery),
        on: p.id == sd.project_id,
        select: %{p | hours: sd.duration |> coalesce(0) |> type(:integer)}
      )

    query = apply_archive_filter(query, archived?)
    query = apply_search_and_order(query, search)

    results =
      query
      |> Firmowid.Repo.all(maybe_unnamed(search))
      |> Enum.map(&seconds_to_hours/1)

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

  defp seconds_to_hours(%{hours: seconds} = project) do
    hours = seconds |> Kernel./(3600) |> Float.ceil() |> trunc()
    %{project | hours: hours}
  end
end
