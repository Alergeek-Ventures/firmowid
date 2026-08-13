defmodule Firmowid.Ash.Timetracker do
  @moduledoc """
  Ash domain for time tracking.

  Manages sessions, projects, project memberships, hours records, and leave
  requests. All reads and writes go through Ash actions with policy-based
  authorization and attribute multitenancy via `organization_id`.
  """
  use Ash.Domain,
    extensions: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Timetracker.LeaveRequest
  alias Firmowid.Ash.Timetracker.Session

  require Ash.Query

  resources do
    resource Firmowid.Ash.Timetracker.HoursRecord do
      define :list_hours_records, action: :list
    end

    resource LeaveRequest do
      define :create_leave_request, action: :create
      define :get_leave_request, action: :read, get_by: [:id]
      define :list_leave_requests_for_user, action: :list_for_user, args: [:user_id]
      define :accept_leave_request, action: :accept, get_by: [:id]
      define :decline_leave_request, action: :decline, get_by: [:id]
    end

    resource Firmowid.Ash.Timetracker.Project do
      define :list_projects, action: :list
      define :get_project, action: :get
    end

    resource Firmowid.Ash.Timetracker.ProjectUser

    resource Session do
      define :list_sessions, action: :list
      define :get_session_by_id, action: :read, get_by: [:id]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
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
  @spec months_with_sessions(map(), keyword()) :: [NaiveDateTime.t()]
  def months_with_sessions(filters, scope) do
    filters
    |> query_to_list_sessions(scope: scope)
    |> Ash.Query.distinct(:month_start)
    |> Ash.Query.distinct_sort(month_start: :desc)
    |> Ash.Query.sort(month_start: :desc)
    |> Ash.Query.load(:month_start)
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.month_start)
  end

  def years_with_leave_requests(user_id, scope) do
    %{user_id: user_id}
    |> query_to_list_leave_requests_for_user(scope: scope)
    |> Ash.Query.filter(status != :pending)
    |> Ash.Query.select([:starts_on, :ends_on])
    |> Ash.read!(scope: scope)
    |> Enum.flat_map(&[&1.starts_on.year, &1.ends_on.year])
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end
end
