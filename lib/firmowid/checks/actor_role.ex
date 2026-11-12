defmodule Firmowid.Checks.ActorRole do
  @moduledoc """
  Policy check that returns true when the actor is a `User` whose organization
  member has exactly the specified role.

  A `User` actor must have its active `member` loaded (see `Firmowid.Core.load_member/2`);
  a user without one has no role. The role counts only inside the member's
  organization: a tenant must be that organization, and on a multitenant
  resource the role never reaches across tenants (a `:bypass` action, or an
  `:allow_global` action or global resource called without a tenant). A
  tenantless check of a tenant-bound action, such as an `Ash.can?/3` before the
  call, counts. A superuser keeps their role everywhere: the superuser worksheet
  reads other organizations with it.

  ## Options

  - `role` — the required role (required)

  ## Usage

      bypass {ActorRole, role: :admin} do
        authorize_if always()
      end
  """
  use Ash.Policy.SimpleCheck

  alias Ash.Resource.Info
  alias Firmowid.Core.Member
  alias Firmowid.Core.User

  @impl true
  def describe(opts), do: "actor is a User with role #{inspect(Keyword.get(opts, :role))}"

  @impl true
  def match?(actor, context, opts), do: {:ok, role(actor, context) == Keyword.fetch!(opts, :role)}

  @doc "Returns the role of the actor's `member/2`, or `nil` without one."
  @spec role(term(), map()) :: Firmowid.Core.UserRole.t() | nil
  def role(actor, context) do
    case member(actor, context) do
      %{role: role} -> role
      nil -> nil
    end
  end

  @doc """
  Returns the actor's organization member when the policy context acts inside
  that member's organization, or `nil`.
  """
  @spec member(term(), map()) :: Member.t() | nil
  def member(actor, context) do
    case loaded_member(actor) do
      %{organization_id: organization_id} = member ->
        if in_organization?(context, organization_id, actor.system_role), do: member

      nil ->
        nil
    end
  end

  # Every resource depends on this check at compile time, so it matches the
  # actor with `is_struct/2` guards: a `%User{}` pattern in a function head adds
  # a runtime dependency on `User`, which would recompile all those resources
  # whenever anything `User` reaches at runtime changes.
  defp loaded_member(%{member: member} = user) when is_struct(user, User) and is_struct(member, Member), do: member

  defp loaded_member(%{member: nil} = user) when is_struct(user, User), do: nil

  defp loaded_member(%{member: %Ash.NotLoaded{}} = user) when is_struct(user, User),
    do: raise(ArgumentError, "the actor's member is not loaded: user #{user.id}")

  defp loaded_member(_actor), do: nil

  defp in_organization?(_context, _organization_id, :superuser), do: true

  # Field policies check a synthetic query without an action; the authorizer
  # carries the one being authorized.
  defp in_organization?(%{subject: subject} = context, organization_id, _system_role) do
    %{to_tenant: tenant, resource: resource} = subject
    multitenancy = Map.get(Map.get(context, :action) || subject.action, :multitenancy)

    cond do
      is_nil(Info.multitenancy_strategy(resource)) ->
        tenant in [nil, organization_id]

      multitenancy in [:bypass, :bypass_all] ->
        false

      not is_nil(tenant) ->
        tenant == organization_id

      Info.multitenancy_global?(resource) ->
        false

      true ->
        multitenancy != :allow_global
    end
  end
end
