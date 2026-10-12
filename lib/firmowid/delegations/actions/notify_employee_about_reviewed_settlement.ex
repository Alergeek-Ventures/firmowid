defmodule Firmowid.Delegations.Actions.NotifyEmployeeAboutReviewedSettlement do
  @moduledoc """
  Emails the employee that their delegation settlement was accepted or returned for corrections.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Delegations
  alias Firmowid.Delegations.DelegationEmails
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @impl true
  def run(%{arguments: %{signal: signal}}, _opts, _context) do
    organization_id = signal.organization_id

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :leave_notifier},
      tenant: organization_id
    }

    with {:ok, delegation} <-
           Delegations.get_delegation(signal.delegation_id,
             scope: scope,
             load: [:expenses, member: :user]
           ),
         {:ok, _email} <-
           DelegationEmails.deliver_reviewed_settlement(
             delegation,
             delegation.member,
             signal.status,
             signal.reason
           ) do
      :ok
    end
  end
end
