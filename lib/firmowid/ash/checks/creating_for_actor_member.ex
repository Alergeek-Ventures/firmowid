defmodule Firmowid.Ash.Checks.CreatingForActorMember do
  @moduledoc """
  Policy check for create actions: the record's `member_id` is the actor's own
  organization member.

  The member counterpart of `relating_to_actor/1` for resources that belong to
  a `Member` rather than to the acting `User`.
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Core.User

  @impl true
  def describe(_opts), do: "record is created for the actor's member"

  @impl true
  def match?(%User{member: %Member{id: member_id}}, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    {:ok, Ash.Changeset.get_attribute(changeset, :member_id) == member_id}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
