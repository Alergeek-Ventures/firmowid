defmodule Firmowid.Ash.Timetracker do
  @moduledoc """
  Ash domain for time tracking.

  Manages sessions, projects, project memberships, and hours records.
  All reads and writes go through Ash actions with policy-based
  authorization and attribute multitenancy via `organization_id`.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Timetracker.HoursRecord
    resource Firmowid.Ash.Timetracker.Project
    resource Firmowid.Ash.Timetracker.ProjectUser
    resource Firmowid.Ash.Timetracker.Session
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
