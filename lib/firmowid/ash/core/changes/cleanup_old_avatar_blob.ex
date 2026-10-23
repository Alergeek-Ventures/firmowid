defmodule Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob do
  @moduledoc """
  After updating an avatar owner, destroys the previous blob (if any)
  from S3 and the database.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query

  @blob_references [
    {Member, :avatar_blob_id},
    {Firmowid.Ash.Invoicing.CostInvoice, :blob_id},
    {Firmowid.Ash.Payroll.UserEmploymentContract, :blob_id},
    {Firmowid.Ash.Timetracker.HoursRecord, :blob_id},
    {Firmowid.Ash.Timetracker.LeaveRequest, :blob_id},
    {Firmowid.Ash.Delegations.Delegation, :signed_command_blob_id},
    {DelegationExpense, :blob_id},
    {DelegationExpense, :statement_blob_id},
    {Firmowid.Ash.Delegations.DelegationExpenseRelatedBlob, :blob_id},
    {Organization, :avatar_blob_id}
  ]

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      old_blob_id = Ash.Changeset.get_data(changeset, :avatar_blob_id)
      tenant = Map.get(record, :organization_id, record.id)

      # Each referencing resource lets this actor read only rows pointing at
      # `blob_id`, so the check also sees references hidden from the owner.
      scope = %Scope{
        actor: %SystemActor{org_id: tenant, role: :avatar_cleanup, blob_id: old_blob_id},
        tenant: tenant
      }

      if old_blob_id && old_blob_id != record.avatar_blob_id do
        # Serialize deletion with concurrent FK references to this same blob.
        old_blob = Blobs.get_blob!(old_blob_id, scope: scope, lock: :for_update)

        # Avatar uploads can reuse a document blob by checksum; its own
        # processing lifecycle decides when to remove it.
        if old_blob.processing_target == :none and avatar_blob_unreferenced?(old_blob_id, scope) do
          Blobs.destroy_blob!(old_blob, scope: scope)
        end
      end

      {:ok, record}
    end)
  end

  defp avatar_blob_unreferenced?(blob_id, scope) do
    not Enum.any?(@blob_references, fn {resource, field} ->
      resource
      |> Ash.Query.filter(^[{field, blob_id}])
      |> Ash.Query.for_read(:read, %{}, scope: scope)
      |> Ash.exists?(scope: scope)
    end)
  end
end
