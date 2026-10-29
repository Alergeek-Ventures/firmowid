defmodule Firmowid.Checks.CreatingForActorMember do
  @moduledoc """
  Policy check for create actions: the record's `member_id` is the actor's own
  organization member.

  The member counterpart of `relating_to_actor/1` for resources that belong to
  a `Member` rather than to the acting `User`.
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Core.Member
  alias Firmowid.Core.User

  @impl true
  def describe(_opts), do: "record is created for the actor's member"

  # `is_struct/2` instead of `%User{}` in the head keeps this compile-time
  # dependency of resources free of a runtime dependency on `User`.
  @impl true
  def match?(%{member: member} = actor, %{subject: %Ash.Changeset{} = changeset}, _opts)
      when is_struct(actor, User) and is_struct(member, Member) do
    {:ok, Ash.Changeset.get_attribute(changeset, :member_id) == member.id}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
