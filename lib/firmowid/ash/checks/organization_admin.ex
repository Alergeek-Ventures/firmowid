defmodule Firmowid.Ash.Checks.OrganizationAdmin do
  @moduledoc """
  Policy check that matches records of the actor's organization when the actor is
  an organization admin.

  Use it on non-multitenant resources, where `actor_attribute_equals(:role, :admin)`
  alone would let an admin act on records of any organization.
  """
  use Ash.Policy.FilterCheck

  @impl true
  def describe(_opts), do: "actor is an admin of the record's organization"

  @impl true
  def filter(_actor, _context, _opts) do
    expr(
      ^actor(:role) == :admin and not is_nil(^actor(:organization_id)) and
        organization_id == ^actor(:organization_id)
    )
  end
end
