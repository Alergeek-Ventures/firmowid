defmodule Firmowid.Ash.Delegations.Workers.DelegationEmailWorker do
  @moduledoc "Sends delegation submission notifications to organization admins."

  use Oban.Worker, queue: :notification_emails, max_attempts: 3

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationEmails
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  @spec enqueue(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(delegation_id, organization_id) do
    %{delegation_id: delegation_id, organization_id: organization_id}
    |> new()
    |> Firmowid.Oban.insert(organization_id: organization_id)
  end

  @impl true
  def perform(%Oban.Job{args: %{"delegation_id" => delegation_id, "organization_id" => organization_id}}) do
    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :leave_notifier},
      tenant: organization_id
    }

    with {:ok, delegation} <-
           Delegations.get_delegation(delegation_id, scope: scope, load: [:user]),
         admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope),
         {:ok, _email} <-
           DelegationEmails.deliver_new_delegation(admins, delegation, delegation.user) do
      :ok
    end
  end
end
