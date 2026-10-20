defmodule Firmowid.Ash.Checks.OrganizationMemberAdmin do
  @moduledoc """
  Policy check that matches users who are members of the actor's organization when
  the actor is an admin of it.

  Users are not multitenant; their `member` ties them to an organization, so this
  keeps matching users whose account has left the organization.
  """
  use Ash.Policy.FilterCheck

  alias Firmowid.Ash.Checks.ActorRole

  @impl true
  def describe(_opts), do: "actor is an admin of the user's organization"

  @impl true
  def filter(actor, _context, _opts) do
    if ActorRole.role(actor) == :admin do
      expr(
        not is_nil(^actor(:organization_id)) and
          exists(member, organization_id == ^actor(:organization_id))
      )
    else
      false
    end
  end
end
