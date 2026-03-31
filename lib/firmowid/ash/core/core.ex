defmodule Firmowid.Ash.Core do
  @moduledoc """
  Core domain — read-only Ash wrappers for shared entities.

  These wrap existing Ecto tables so that other Ash domains (e.g. Timetracker)
  can reference them in relationships. All writes still go through the original
  Ecto contexts during migration.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Core.Organization
    resource Firmowid.Ash.Core.User
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
