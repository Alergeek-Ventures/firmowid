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

      digest =
        Ash.load!(digest, [:organization, :cost_invoices],
          tenant: digest.organization_id,
          actor: actor
        )

      selected_admin_user_ids = Ash.Changeset.get_argument(changeset, :admin_user_ids)

      admins =
        %{status: :active, role: :admin}
        |> Core.list_users!(
          tenant: digest.organization_id,
          actor: actor
        )
        |> maybe_filter_admins(selected_admin_user_ids)

      log_digest_delivery_attempt(digest, admins, selected_admin_user_ids)

      if digest.cost_invoices == [] do
        Ash.Changeset.add_error(
          changeset,
          InvalidAttribute.exception(
            field: :delivered_at,
            message: "cannot send KSeF digest without persisted invoices"
          )
        )
      else
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
      end
    end)
  end

  defp maybe_filter_admins(admins, nil), do: admins

  defp maybe_filter_admins(admins, admin_user_ids) do
    Enum.filter(admins, &(&1.id in admin_user_ids))
  end

  defp log_digest_delivery_attempt(digest, admins, selected_admin_user_ids) do
    Logger.info(
      "Sending KSeF digest for organization_id=#{digest.organization_id} " <>
        "organization_name=#{digest.organization.name}"
    )

    Logger.info("Digest contains #{length(digest.cost_invoices)} invoice(s) in the selected window")

    Logger.info("Digest recipients admin_count=#{length(admins)} admin_ids=#{inspect(Enum.map(admins, & &1.id))}")

    if selected_admin_user_ids do
      Logger.info("Digest recipient filter admin_user_ids=#{inspect(selected_admin_user_ids)}")
    end
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
