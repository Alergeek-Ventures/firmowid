defmodule Firmowid.Delegations.Actions.NotifyAdminsAboutSubmittedSettlement do
  @moduledoc """
  Emails organization admins that an employee submitted a signed settlement.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Core
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
         admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope),
         {:ok, _email} <-
           DelegationEmails.deliver_submitted_settlement(admins, delegation, delegation.member) do
      :ok
    end
  end
end
