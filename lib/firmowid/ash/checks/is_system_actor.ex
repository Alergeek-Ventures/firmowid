defmodule Firmowid.Ash.Checks.IsSystemActor do
  @moduledoc """
  Policy check that returns true when the actor is a `Firmowid.Ash.SystemActor`.

  Used as a bypass gate to distinguish human users from internal system processes.
  System actors represent background jobs and automated pipelines.

  ## Usage

      bypass IsSystemActor do
        authorize_if always()
      end

      # Or to explicitly deny system actors:
      bypass IsSystemActor do
        forbid_if always()
      end
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Ash.SystemActor

  @impl true
  def describe(_opts), do: "actor is a SystemActor"

  @impl true
  def match?(%SystemActor{}, _context, _opts), do: {:ok, true}
  def match?(_actor, _context, _opts), do: {:ok, false}
end
