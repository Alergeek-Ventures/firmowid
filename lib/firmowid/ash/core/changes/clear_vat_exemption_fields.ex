defmodule Firmowid.Ash.Core.Changes.ClearVatExemptionFields do
  @moduledoc """
  Clears VAT exemption fields based on business rules:
  - Sets `vat_exemption_type` to nil when `is_vat_payer == true`
  - Sets `vat_exemption_basis` to nil when `vat_exemption_type != :other`
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> clear_type_if_vat_payer()
    |> clear_basis_if_not_other()
  end

  defp clear_type_if_vat_payer(changeset) do
    if Ash.Changeset.get_attribute(changeset, :is_vat_payer) == true do
      Ash.Changeset.force_change_attribute(changeset, :vat_exemption_type, nil)
    else
      changeset
    end
  end

  defp clear_basis_if_not_other(changeset) do
    case Ash.Changeset.get_attribute(changeset, :vat_exemption_type) do
      :other -> changeset
      _ -> Ash.Changeset.force_change_attribute(changeset, :vat_exemption_basis, nil)
    end
  end
end
