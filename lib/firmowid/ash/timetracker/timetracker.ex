defmodule Firmowid.Ash.Timetracker do
  @moduledoc """
  Ash domain for time tracking.

  Wraps the existing `sessions` and `projects` tables. During migration, both
  this domain and the old `Firmowid.Timetracker` context coexist — the old
  context handles writes from the current UI, while this domain is used by
  the new UI and AshAI/MCP.
  """
  use Ash.Domain

  authorization do
    authorize(:by_default)
    require_actor?(true)
  end

  resources do
    resource(Firmowid.Ash.Timetracker.Project)
    resource(Firmowid.Ash.Timetracker.Session)
  end
end
