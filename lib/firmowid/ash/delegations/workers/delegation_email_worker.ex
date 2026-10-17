defmodule Firmowid.Ash.Delegations.Workers.DelegationEmailWorker do
  @moduledoc "Sends delegation request, approval, and settlement-review notification emails."

  use Oban.Worker, queue: :notification_emails, max_attempts: 3

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationEmails
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  @doc "Enqueues an admin notification for a submitted delegation."
  @spec enqueue(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(delegation_id, organization_id) do
    %{delegation_id: delegation_id, organization_id: organization_id, notification: "submitted"}
    |> new()
    |> Firmowid.Oban.insert(organization_id: organization_id)
  end

  @doc "Enqueues an employee confirmation for an approved delegation."
  @spec enqueue_approval(String.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_approval(delegation_id, organization_id) do
    %{delegation_id: delegation_id, organization_id: organization_id, notification: "approved"}
    |> new()
    |> Firmowid.Oban.insert(organization_id: organization_id)
  end

  @doc "Enqueues an admin notification after an employee submits a signed settlement."
  @spec enqueue_settlement_submission(String.t(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_settlement_submission(delegation_id, organization_id) do
    %{
      delegation_id: delegation_id,
      organization_id: organization_id,
      notification: "settlement_submitted"
    }
    |> new()
    |> Firmowid.Oban.insert(organization_id: organization_id)
  end

  @impl true
  def perform(%Oban.Job{args: %{"delegation_id" => delegation_id, "organization_id" => organization_id} = args}) do
    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :leave_notifier},
      tenant: organization_id
    }

    with {:ok, delegation} <-
           Delegations.get_delegation(delegation_id, scope: scope, load: [:user, :expenses]) do
      deliver(args["notification"], delegation, scope)
    end
  end

  defp deliver("approved", delegation, _scope) do
    with {:ok, _email} <-
           DelegationEmails.deliver_approved_delegation(delegation, delegation.user),
         do: :ok
  end

  defp deliver("settlement_submitted", delegation, scope) do
    admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope)

    with {:ok, _email} <-
           DelegationEmails.deliver_submitted_settlement(
             admins,
             delegation,
             delegation.user
           ),
         do: :ok
  end

  defp deliver(notification, delegation, scope) when notification in [nil, "submitted"] do
    admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope)

    with {:ok, _email} <-
           DelegationEmails.deliver_new_delegation(admins, delegation, delegation.user),
         do: :ok
  end
end
