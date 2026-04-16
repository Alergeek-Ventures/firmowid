defmodule Firmowid.Ash.Invoicing.Changes.VerifyKsefInvoiceDigestCreate do
  @moduledoc """
  Guards KSeF digest creation against empty or partially-persisted invoice memberships.

  This prevents orphan digest rows from being considered valid when the selected
  invoice ids were not actually attached to the digest.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.SystemActor

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> validate_invoice_ids_present()
    |> verify_persisted_memberships()
  end

  defp validate_invoice_ids_present(changeset) do
    case Ash.Changeset.get_argument(changeset, :cost_invoice_ids) do
      invoice_ids when is_list(invoice_ids) and invoice_ids != [] ->
        changeset

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :cost_invoice_ids,
          message: "must contain at least one invoice"
        )
    end
  end

  defp verify_persisted_memberships(changeset) do
    Ash.Changeset.after_action(changeset, fn changeset, digest ->
      expected_invoice_ids = Ash.Changeset.get_argument(changeset, :cost_invoice_ids) || []
      actor = %SystemActor{org_id: digest.organization_id, role: :ksef_digest}

      digest =
        Ash.load!(digest, [:digest_items, :cost_invoices, :cost_invoices_join_assoc],
          tenant: digest.organization_id,
          actor: actor
        )

      persisted_invoice_ids = Enum.map(digest.cost_invoices, & &1.id)
      join_assoc_count = length(digest.cost_invoices_join_assoc)

      if length(persisted_invoice_ids) == length(expected_invoice_ids) and
           MapSet.new(persisted_invoice_ids) == MapSet.new(expected_invoice_ids) do
        {:ok, digest}
      else
        Logger.error(
          "KSeF digest create verification failed digest_id=#{digest.id} organization_id=#{digest.organization_id} " <>
            "expected_invoice_ids=#{inspect(expected_invoice_ids)} persisted_invoice_ids=#{inspect(persisted_invoice_ids)} " <>
            "digest_item_count=#{length(digest.digest_items)} join_assoc_count=#{join_assoc_count}"
        )

        {:error,
         InvalidAttribute.exception(
           field: :cost_invoice_ids,
           message: "failed to persist all digest invoice memberships"
         )}
      end
    end)
  end
end
