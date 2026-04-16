defmodule Firmowid.Ash.Invoicing.Changes.SendKsefInvoiceDigest do
  @moduledoc """
  Delivers a persisted KSeF invoice digest to all active organization admins.

  The digest is marked as delivered only when every recipient email succeeds.
  """
  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Invoicing.Digests.Email
  alias Firmowid.Ash.SystemActor

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      digest = changeset.data
      actor = %SystemActor{org_id: digest.organization_id, role: :ksef_digest}

      admins =
        Core.list_users!(
          %{status: :active, role: :admin},
          tenant: digest.organization_id,
          actor: actor
        )

      log_digest_delivery_attempt(digest, admins)

      case deliver_to_admins(admins, digest) do
        :ok ->
          Ash.Changeset.force_change_attribute(changeset, :delivered_at, DateTime.utc_now())

        {:error, failures} ->
          Ash.Changeset.add_error(
            changeset,
            InvalidAttribute.exception(
              field: :delivered_at,
              message: Enum.map_join(failures, "; ", &format_failure/1)
            )
          )
      end
    end)
  end

  defp log_digest_delivery_attempt(digest, admins) do
    Logger.info("Sending KSeF digest for organization #{digest.organization_id} (#{digest.organization.name})")

    Logger.info("Digest contains #{length(digest.cost_invoices)} invoice(s)")

    Logger.info("Digest recipients: #{Enum.map_join(admins, ", ", & &1.email)}")
  end

  defp deliver_to_admins(admins, digest) do
    failures =
      admins
      |> Enum.map(fn admin ->
        case Email.deliver_ksef_invoice_digest(admin, digest, digest.cost_invoices) do
          {:ok, _email} -> nil
          {:error, reason} -> {admin.email, reason}
        end
      end)
      |> Enum.reject(&is_nil/1)

    if failures == [], do: :ok, else: {:error, failures}
  end

  defp format_failure({email, reason}), do: "#{email}: #{inspect(reason)}"
end
