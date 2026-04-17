defmodule Firmowid.Ash.Timetracker do
  @moduledoc """
  Ash domain for time tracking.

  Manages sessions, projects, project memberships, and hours records.
  All reads and writes go through Ash actions with policy-based
  authorization and attribute multitenancy via `organization_id`.
  """
  use Ash.Domain,
    extensions: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Timetracker.Session

  require Ash.Query

  resources do
    resource Firmowid.Ash.Timetracker.HoursRecord do
      define :list_hours_records, action: :list
    end

    resource Firmowid.Ash.Timetracker.Project do
      define :list_projects, action: :list
      define :get_project, action: :get
    end

    resource Firmowid.Ash.Timetracker.ProjectUser

    resource Session do
      define :list_sessions, action: :list
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
    Session
    |> Ash.Query.for_read(:list, filters, scope: scope)
    |> Ash.Query.distinct(:month_start)
    |> Ash.Query.distinct_sort(month_start: :desc)
    |> Ash.Query.sort(month_start: :desc)
    |> Ash.Query.load(:month_start)
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.month_start)
  end
end
