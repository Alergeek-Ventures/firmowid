defmodule Firmowid.Checks.ActorRole do
  @moduledoc """
  Policy check that returns true when the actor is a `User` whose organization
  member has exactly the specified role.

  A `User` actor must have its active `member` loaded (see `Firmowid.Core.load_member/2`);
  a user without one has no role.

  ## Options

  - `role` — the required role (required)

  ## Usage

      bypass {ActorRole, role: :admin} do
        authorize_if always()
      end
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Core.Member
  alias Firmowid.Core.User

  @impl true
  def describe(opts), do: "actor is a User with role #{inspect(Keyword.get(opts, :role))}"

  @impl true
  def match?(actor, _context, opts), do: {:ok, role(actor) == Keyword.fetch!(opts, :role)}

  # Every resource depends on this check at compile time, so it matches the
  # actor with `is_struct/2` guards: a `%User{}` pattern in a public function
  # head adds a runtime dependency on `User`, which would recompile all those
  # resources whenever anything `User` reaches at runtime changes.
  @doc "Returns the role of the actor's organization member, or `nil` for actors without one."
  @spec role(term()) :: Firmowid.Core.UserRole.t() | nil
  def role(%{member: member} = user) when is_struct(user, User) and is_struct(member, Member), do: member.role

  def role(%{member: nil} = user) when is_struct(user, User), do: nil

  def role(%{member: %Ash.NotLoaded{}} = user) when is_struct(user, User),
    do: raise(ArgumentError, "the actor's member is not loaded: user #{user.id}")

  def role(_actor), do: nil
end
