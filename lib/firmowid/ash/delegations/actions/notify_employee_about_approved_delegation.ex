defmodule Firmowid.Ash.Delegations.Actions.NotifyEmployeeAboutApprovedDelegation do
  @moduledoc """
  Emails the employee that their delegation was approved.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationEmails
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  @impl true
  def run(%{arguments: %{signal: signal}}, _opts, _context) do
    organization_id = signal.organization_id

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :leave_notifier},
      tenant: organization_id
    }

    with {:ok, delegation} <-
           Delegations.get_delegation(signal.delegation_id, scope: scope, load: [member: :user]),
         {:ok, _email} <-
           DelegationEmails.deliver_approved_delegation(delegation, delegation.member.user) do
      :ok
    end
  end
end
