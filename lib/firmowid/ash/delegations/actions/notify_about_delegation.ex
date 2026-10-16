defmodule Firmowid.Ash.Delegations.Actions.NotifyAboutDelegation do
  @moduledoc """
  Sends delegation notification emails: to admins when a delegation is
  submitted, and to the employee when it is approved.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationEmails
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  @impl true
  def run(%{arguments: %{signal: signal}}, opts, _context) do
    organization_id = signal.organization_id

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :leave_notifier},
      tenant: organization_id
    }

    with {:ok, delegation} <-
           Delegations.get_delegation(signal.delegation_id, scope: scope, load: [:user]) do
      deliver(opts[:notification], delegation, scope)
    end
  end

  defp deliver(:approved, delegation, _scope) do
    with {:ok, _email} <-
           DelegationEmails.deliver_approved_delegation(delegation, delegation.user),
         do: :ok
  end

  defp deliver(:submitted, delegation, scope) do
    admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope)

    with {:ok, _email} <-
           DelegationEmails.deliver_new_delegation(admins, delegation, delegation.user),
         do: :ok
  end
end
