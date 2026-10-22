defmodule Firmowid.Ash.Checks.OrganizationAdmin do
  @moduledoc """
  Policy check that matches records of the actor's organization when the actor is
  an organization admin.

  Use it on non-multitenant resources, where `{ActorRole, role: :admin}` alone
  would let an admin act on records of any organization.
  """
  use Ash.Policy.FilterCheck

  alias Firmowid.Ash.Checks.ActorRole

  @impl true
  def describe(_opts), do: "actor is an admin of the record's organization"

  @impl true
  def filter(actor, _context, _opts) do
    if ActorRole.role(actor) == :admin do
      expr(
        not is_nil(^actor([:member, :organization_id])) and
          organization_id == ^actor([:member, :organization_id])
      )
    else
      false
    end
  end
end
