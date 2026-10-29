defmodule Firmowid.Checks.AtLeastRole do
  @moduledoc """
  Policy check that returns true when the actor is a `User` whose organization
  member has a role at least as privileged as the specified minimum role.

  ## Role Hierarchy (lowest to highest)

      :employee < :invoicing < :accountant < :admin

  The ordered list comes from `Firmowid.Core.UserRole.roles/0`.

  ## Options

  - `role` — the minimum required role (required)

  ## Usage

      policy action_type(:read) do
        authorize_if {AtLeastRole, role: :invoicing}
      end

      policy action_type([:create, :update]) do
        authorize_if {AtLeastRole, role: :accountant}
      end
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Core.UserRole

  @impl true
  def describe(opts) do
    role = Keyword.get(opts, :role)
    "actor is a User with role >= #{inspect(role)}"
  end

  @impl true
  def match?(actor, _context, opts) do
    case {role_index(ActorRole.role(actor)), role_index(Keyword.get(opts, :role))} do
      {nil, _} -> {:ok, false}
      {_, nil} -> {:ok, false}
      {actor_index, minimum_index} -> {:ok, actor_index >= minimum_index}
    end
  end

  defp role_index(role), do: Enum.find_index(UserRole.roles(), &(&1 == role))
end
