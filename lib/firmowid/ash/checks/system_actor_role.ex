defmodule Firmowid.Ash.Checks.SystemActorRole do
  @moduledoc """
  Policy check that returns true when the actor is a `SystemActor` with one of
  the specified roles.

  ## Options

  - `roles` — list of allowed `SystemActor` roles (required)

  ## Usage

      bypass {SystemActorRole, roles: [:invoice_matcher]} do
        authorize_if always()
      end

      bypass {SystemActorRole, roles: [:cost_invoice_processor, :sales_invoice_processor]} do
        authorize_if action_type(:read)
      end
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Ash.SystemActor

  @impl true
  def describe(opts) do
    roles = Keyword.get(opts, :roles, [])
    "actor is a SystemActor with role in #{inspect(roles)}"
  end

  @impl true
  def match?(%SystemActor{role: role}, _context, opts) do
    case Keyword.fetch(opts, :roles) do
      {:ok, roles} -> {:ok, role in roles}
      :error -> {:ok, false}
    end
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
