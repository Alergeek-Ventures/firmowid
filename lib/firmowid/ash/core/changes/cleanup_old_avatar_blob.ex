defmodule Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob do
  @moduledoc """
  After updating an avatar owner, destroys the previous blob from S3 and the
  database once nothing references it anymore. Document blobs retain their own
  processing lifecycle even when their contents were reused as an avatar.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Delegations.DelegationExpenseRelatedBlob
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Payroll.UserEmploymentContract
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Ash.Timetracker.LeaveRequest

  require Ash.Query

  @blob_references [
    {Member, :avatar_blob_id},
    {Organization, :avatar_blob_id},
    {CostInvoice, :blob_id},
    {UserEmploymentContract, :blob_id},
    {HoursRecord, :blob_id},
    {LeaveRequest, :blob_id},
    {Delegation, :signed_command_blob_id},
    {DelegationExpense, :blob_id},
    {DelegationExpense, :statement_blob_id},
    {DelegationExpenseRelatedBlob, :blob_id}
  ]

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, record ->
      old_blob_id = Ash.Changeset.get_data(changeset, :avatar_blob_id)

      if old_blob_id && old_blob_id != record.avatar_blob_id do
        tenant = Map.get(record, :organization_id, record.id)

        scope = %Scope{
          actor: %SystemActor{org_id: tenant, role: :avatar_cleanup, blob_id: old_blob_id},
          tenant: tenant
        }

        # Serialize deletion with concurrent FK references to this same blob.
        old_blob = Blobs.get_blob!(old_blob_id, scope: scope, lock: :for_update)

        if old_blob.processing_target == :none and unreferenced?(old_blob_id, scope) do
          Blobs.destroy_blob!(old_blob, scope: scope)
        end
      end

      {:ok, record}
    end)
  end

  defp unreferenced?(blob_id, scope) do
    not Enum.any?(@blob_references, fn {resource, field} ->
      resource
      |> Ash.Query.filter(^[{field, blob_id}])
      |> Ash.Query.for_read(:read, %{}, scope: scope)
      |> Ash.exists?(scope: scope)
    end)
  end
end
