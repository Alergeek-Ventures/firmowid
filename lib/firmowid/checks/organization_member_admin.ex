defmodule Firmowid.Checks.OrganizationMemberAdmin do
  @moduledoc """
  Policy check that matches users who are members of the actor's organization when
  the actor is an admin of it.

  Users are not multitenant; their `member` ties them to an organization, so this
  keeps matching users whose member is archived. Pass `active: true` to match only
  users whose member there is not archived.
  """
  use Ash.Policy.FilterCheck

  alias Firmowid.Checks.ActorRole

  @impl true
  def describe(opts) do
    if opts[:active],
      do: "actor is an admin of the user's active organization",
      else: "actor is an admin of the user's organization"
  end

  @impl true
  def filter(actor, _context, opts) do
    cond do
      ActorRole.role(actor) != :admin ->
        false

      opts[:active] ->
        expr(
          not is_nil(^actor([:member, :organization_id])) and
            exists(
              member,
              organization_id == ^actor([:member, :organization_id]) and is_nil(archived_at)
            )
        )

      true ->
        expr(
          not is_nil(^actor([:member, :organization_id])) and
            exists(member, organization_id == ^actor([:member, :organization_id]))
        )
    end
  end
end
