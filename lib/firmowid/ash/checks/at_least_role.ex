defmodule Firmowid.Ash.Checks.AtLeastRole do
  @moduledoc """
  Policy check that returns true when the actor is a `User` with a role at least
  as privileged as the specified minimum role.

  ## Role Hierarchy (lowest to highest)

      :employee < :invoicing < :accountant < :admin

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

  alias Firmowid.Ash.Core.User

  @role_hierarchy [:employee, :invoicing, :accountant, :admin]

  @impl true
  def describe(opts) do
    role = Keyword.get(opts, :role)
    "actor is a User with role >= #{inspect(role)}"
  end

  @impl true
  def match?(%User{role: actor_role}, _context, opts) do
    case Keyword.fetch(opts, :role) do
      {:ok, minimum_role} ->
        actor_index = role_index(actor_role)
        minimum_index = role_index(minimum_role)

        case {actor_index, minimum_index} do
          {nil, _} -> {:ok, false}
          {_, nil} -> {:ok, false}
          {a, m} -> {:ok, a >= m}
        end

      :error ->
        {:ok, false}
    end
  end

  def match?(_actor, _context, _opts), do: {:ok, false}

  defp role_index(role), do: Enum.find_index(@role_hierarchy, &(&1 == role))
end
