defmodule Firmowid.Ash.Checks.ActorRole do
  @moduledoc """
  Policy check that returns true when the actor is a `User` whose organization
  member has exactly the specified role.

  A `User` actor in an organization must have its `member` loaded (see
  `FirmowidWeb.Infrastructure.UserAuth`); a user without an organization has no role.

  ## Options

  - `role` — the required role (required)

  ## Usage

      bypass {ActorRole, role: :admin} do
        authorize_if always()
      end
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Core.User

  @impl true
  def describe(opts), do: "actor is a User with role #{inspect(Keyword.get(opts, :role))}"

  @impl true
  def match?(actor, _context, opts), do: {:ok, role(actor) == Keyword.fetch!(opts, :role)}

  @doc "Returns the role of the actor's organization member, or `nil` for actors without one."
  @spec role(term()) :: Firmowid.Ash.Core.UserRole.t() | nil
  def role(%User{organization_id: nil}), do: nil
  def role(%User{member: %Member{role: role}}), do: role
  def role(%User{member: nil}), do: nil

  def role(%User{member: %Ash.NotLoaded{}} = user),
    do: raise(ArgumentError, "the actor's member is not loaded: user #{user.id}")

  def role(_actor), do: nil
end
