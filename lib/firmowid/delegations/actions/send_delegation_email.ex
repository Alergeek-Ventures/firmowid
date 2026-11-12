defmodule Firmowid.Delegations.Actions.SendDelegationEmail do
  @moduledoc """
  Emails the people a delegation signal concerns: organization admins about a new delegation or
  a submitted settlement, and the employee about an approval or a settlement review.

  Runs as a system actor bound to the signal's organization, so it reads only that
  organization's delegation and users.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Core
  alias Firmowid.Delegations
  alias Firmowid.Delegations.DelegationEmails
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @impl true
  def run(%{arguments: %{signal: signal}}, opts, _context) do
    email = Keyword.fetch!(opts, :email)

    scope = %Scope{
      actor: %SystemActor{org_id: signal.organization_id, role: :delegation_notifier},
      tenant: signal.organization_id
    }

    with {:ok, delegation} <-
           Delegations.get_delegation(signal.delegation_id, scope: scope, load: load(email)),
         {:ok, _email} <- deliver(email, delegation, signal, scope) do
      :ok
    end
  end

  # The settlement emails show the expenses total.
  defp load(email) when email in [:submitted_settlement, :reviewed_settlement], do: [:expenses, member: :user]

  defp load(_email), do: [member: :user]

  defp deliver(:new_delegation, delegation, _signal, scope),
    do: DelegationEmails.deliver_new_delegation(admins(scope), delegation, delegation.member)

  defp deliver(:approved_delegation, delegation, _signal, _scope),
    do: DelegationEmails.deliver_approved_delegation(delegation, delegation.member)

  defp deliver(:submitted_settlement, delegation, _signal, scope),
    do: DelegationEmails.deliver_submitted_settlement(admins(scope), delegation, delegation.member)

  defp deliver(:reviewed_settlement, delegation, signal, _scope),
    do: DelegationEmails.deliver_reviewed_settlement(delegation, delegation.member, signal.status, signal.reason)

  defp admins(scope), do: Core.list_users!(%{status: :active, role: :admin}, scope: scope)
end
