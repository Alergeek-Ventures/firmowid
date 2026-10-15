defmodule Firmowid.Ash.Invoicing.Changes.PrepareInvoiceSeller do
  @moduledoc """
  Snapshots the scoped organization's seller details while preparing a new invoice or saved draft.

  An unnumbered document is issued on the day it is prepared, so its issue date is always today.
  A saved draft's date is only the day it was saved and must not backdate its later issuance.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Ash.Core

  @doc "Copies the current organization's details into a new or revised draft."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    case Core.get_organization(context.tenant, Ash.Context.to_opts(context)) do
      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :input,
          message: gettext("The current organization was not found.")
        )

      {:ok, organization} ->
        changeset
        |> Ash.Changeset.force_change_attributes(%{
          seller_display_name: organization.name,
          seller_address: organization.address,
          seller_nip: organization.nip,
          seller_name: nil,
          seller_surname: nil
        })
        |> Ash.Changeset.force_change_attribute(:issue_date, Date.utc_today())
        |> new_invoice_defaults()
        |> default_if_nil(:vat_exemption_type, organization.vat_exemption_type)
        |> default_if_nil(:vat_exemption_basis, organization.vat_exemption_basis)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp new_invoice_defaults(%{action_type: :create} = changeset) do
    changeset
    |> Ash.Changeset.change_new_attribute(:currency, "PLN")
    |> Ash.Changeset.change_new_attribute(:buyer_country, "PL")
  end

  defp new_invoice_defaults(changeset), do: changeset

  defp default_if_nil(changeset, field, default) do
    if is_nil(Ash.Changeset.get_attribute(changeset, field)),
      do: Ash.Changeset.force_change_attribute(changeset, field, default),
      else: changeset
  end
end
