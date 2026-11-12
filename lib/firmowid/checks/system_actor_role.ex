defmodule Firmowid.Checks.SystemActorRole do
  @moduledoc """
  Policy check that returns true when the actor is a `SystemActor` with one of
  the specified roles.

  A system actor built for one organization (`org_id`) holds its role only
  inside that organization, with the same tenant rule as `ActorRole.member/2`.
  An actor without `org_id` is either deliberately cross-tenant or bound to a
  user or record by its own policies, so its role counts everywhere.

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

  alias Firmowid.Checks.ActorRole
  alias Firmowid.SystemActor

  @impl true
  def describe(opts) do
    roles = Keyword.get(opts, :roles, [])
    "actor is a SystemActor with role in #{inspect(roles)}"
  end

  @impl true
  def match?(%SystemActor{role: role, org_id: org_id}, context, opts) do
    {:ok,
     role in Keyword.fetch!(opts, :roles) and
       (is_nil(org_id) or ActorRole.in_organization?(context, org_id))}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
