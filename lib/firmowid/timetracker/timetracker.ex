defmodule Firmowid.Timetracker do
  @moduledoc """
  Ash domain for time tracking.

  Manages sessions, projects, project memberships, hours records, and leave
  requests. All reads and writes go through Ash actions with policy-based
  authorization and attribute multitenancy via `organization_id`.
  """
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, Ash.Policy.Authorizer, AshAi]

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Timetracker.LeaveRequest
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session

  require Ash.Query

  json_api do
    routes do
      base_route "/sessions", Session do
        index :list_user_sessions
        get(:get_current, route: "/current")
        post(:start)
        post(:stop_current, route: "/current/stop")
        patch(:update, read_action: :current_session)
        delete(:destroy, read_action: :current_session)
      end

      base_route "/projects", Project do
        index :list_current_user, paginate?: false
      end
    end
  end

  resources do
    resource Firmowid.Timetracker.HoursRecord do
      define :list_hours_records, action: :list
    end

    resource LeaveRequest do
      define :create_leave_request, action: :create

      define :create_leave_request_with_upload, action: :create_with_upload

      define :get_leave_request, action: :read, get_by: [:id]
      define :list_leave_requests, action: :list
      define :list_leave_requests_for_member, action: :list_for_member, args: [:member_id]
      define :list_current_user_leave_requests, action: :list_current_user
      define :accept_leave_request, action: :accept, get_by: [:id]
      define :decline_leave_request, action: :decline, get_by: [:id]
    end

    resource Project do
      define :list_projects, action: :list
      define :get_project, action: :get
      define :list_current_user_projects, action: :list_current_user
    end

    resource Firmowid.Timetracker.ProjectUser

    resource Session do
      define :list_sessions, action: :list
      define :get_session_by_id, action: :read, get_by: [:id]
    end
  end

  tools do
    tool :list_sessions, Session, :list_user_sessions do
      annotations title: "List work sessions",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Paginated work sessions for the authenticated user, newest first. Default limit is 25 - results are truncated. For whole-month or multi-month analysis paginate with limit+offset (e.g. offset 0, 25, 50) or increase limit. If the returned count equals your limit, fetch the next page with offset+limit. Optionally filter with after_date (UTC, sessions starting on or after that date). Use result_type count to get the total number of matching sessions."
      action_parameters [:sort, :limit, :offset, :filter, :result_type]
      load [:project]

      argument :after_date, :date do
        description "Only return sessions starting on or after this date (UTC)"
      end
    end

    tool :get_current_session, Session, :get_current,
      load: [:project],
      annotations: [
        title: "Get current work session",
        read_only_hint: true,
        destructive_hint: false,
        open_world_hint: false
      ],
      description: "Get the user's currently running session, if any"

    tool :stop_current_session, Session, :stop_current,
      annotations: [
        title: "Stop work session",
        read_only_hint: false,
        destructive_hint: false,
        open_world_hint: false
      ],
      description: "End the authenticated user's currently running work session"

    tool :start_session, Session, :start,
      annotations: [
        title: "Start work session",
        read_only_hint: false,
        destructive_hint: false,
        open_world_hint: false
      ],
      description:
        "Start a work session for the authenticated user now. Optionally pass project_id from list_projects, " <>
          "a title and is_remote. Stops the current session, if any. " <>
          "To log past work use add_sessions instead of stopping the running session."

    tool :edit_session, Session, :edit_current_user_session,
      annotations: [
        title: "Edit work session",
        read_only_hint: false,
        destructive_hint: true,
        open_world_hint: false
      ],
      description:
        "Edit the title, start or end time, project or remote flag of one of the authenticated user's sessions by id. " <>
          "Sessions locked by a submitted hours record cannot be changed."

    tool :add_sessions, Session, :add_completed_sessions,
      annotations: [
        title: "Add past work sessions",
        read_only_hint: false,
        destructive_hint: false,
        open_world_hint: false
      ],
      description:
        "Add one or more completed work sessions of the authenticated user with explicit start and end times, " <>
          "e.g. to fill in a forgotten morning. A running session keeps going untouched; do not stop, edit or restart it. " <>
          "Pass ISO 8601 times with an offset (2026-11-04T08:00:00+01:00 or ...Z); times without one are read as UTC. " <>
          "Times are stored at minute precision. Each session needs a title and a project_id from list_projects, " <>
          "must not end before it starts, stay within one calendar month, last at most 24 hours and must not overlap " <>
          "any other session, including the running one from its start onwards. Months with a submitted hours record are locked. " <>
          "All sessions are added or none; an error names the failing item as sessions.<index>."

    tool :list_leave_requests, LeaveRequest, :list_current_user do
      annotations title: "List leave requests",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Paginated leave and absence requests for the authenticated user, newest first. Default limit is 25 - results are truncated. Paginate with limit+offset (e.g. offset 0, 25, 50) or increase limit. If returned count equals your limit, fetch next page. Supports start_date (requests ending on/after) and end_date (starting on/before) filters. Use result_type count to get total matching requests."
      action_parameters [:sort, :limit, :offset, :filter, :result_type]

      argument :start_date, :date do
        description "Only return requests ending on or after this date"
      end

      argument :end_date, :date do
        description "Only return requests starting on or before this date"
      end
    end

    tool :create_leave_request, LeaveRequest, :create,
      annotations: [
        title: "Request leave",
        read_only_hint: false,
        destructive_hint: false,
        open_world_hint: false
      ],
      description:
        "Submit an absence request for the authenticated user. Use reason indisposition, rest, or other; this action does not support sick, vacation, or unpaid leave. New requests always start with pending status."

    tool :list_projects, Project, :list_current_user do
      annotations title: "List projects",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "List all projects of the authenticated user"
    end
  end

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc "Converts a duration in seconds to whole hours (rounded up)."
  @spec seconds_to_hours(integer()) :: integer()
  def seconds_to_hours(seconds) when is_integer(seconds) do
    ceil(seconds / 3600)
  end

  @doc """
  Returns distinct months (as `NaiveDateTime`) that have sessions matching
  the given filters, newest first.

  Used by management views and hours record index to populate month selectors.
  """
  @spec months_with_sessions(map(), Firmowid.Scope.t()) :: [NaiveDateTime.t()]
  def months_with_sessions(filters, scope) do
    query =
      filters
      |> query_to_list_sessions(scope: scope)
      |> Ash.Query.distinct(:month_start)
      |> Ash.Query.distinct_sort(month_start: :desc)
      |> Ash.Query.sort(month_start: :desc)
      |> Ash.Query.load(:month_start)

    filters
    |> list_sessions!(scope: scope, query: query)
    |> Enum.map(& &1.month_start)
  end

  def years_with_leave_requests(member_id, scope) do
    query =
      member_id
      |> query_to_list_leave_requests_for_member(scope: scope)
      |> Ash.Query.filter(status != :pending)
      |> Ash.Query.select([:starts_on, :ends_on])

    member_id
    |> list_leave_requests_for_member!(scope: scope, query: query)
    |> Enum.flat_map(&[&1.starts_on.year, &1.ends_on.year])
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  def projects_duration_for_month(member_id, %Date{} = date, scope) do
    query =
      %{member_id: member_id}
      |> query_to_list_projects(scope: scope)
      |> Ash.Query.aggregate(:duration, :sum, :sessions,
        field: :duration,
        default: 0,
        query:
          query_to_list_sessions(
            %{member_id: member_id, month: date.month, year: date.year},
            scope: scope
          )
      )

    %{member_id: member_id}
    |> list_projects!(scope: scope, query: query)
    |> Enum.map(fn project ->
      %{id: project.id, name: project.name, duration: project.aggregates[:duration] || 0}
    end)
    |> Enum.sort_by(& &1.duration, :desc)
  end
end
