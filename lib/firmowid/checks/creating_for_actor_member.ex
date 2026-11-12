defmodule Firmowid.Checks.CreatingForActorMember do
  @moduledoc """
  Policy check for create actions: the record's `member_id` is the actor's own
  organization member, inside that member's organization (see `ActorRole.member/2`).

  The member counterpart of `relating_to_actor/1` for resources that belong to
  a `Member` rather than to the acting `User`.
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Checks.ActorRole

  @impl true
  def describe(_opts), do: "record is created for the actor's member"

  @impl true
  def match?(actor, %{subject: %Ash.Changeset{} = changeset} = context, _opts) do
    case ActorRole.member(actor, context) do
      %{id: member_id} -> {:ok, Ash.Changeset.get_attribute(changeset, :member_id) == member_id}
      nil -> {:ok, false}
    end
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
