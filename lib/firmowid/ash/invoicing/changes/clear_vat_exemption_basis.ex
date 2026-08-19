defmodule Firmowid.Ash.Invoicing.Changes.ClearVatExemptionBasis do
  @moduledoc """
  Clears the VAT exemption basis when the exemption type is not `:other`.

  The `:other` type requires a free-text legal basis; all other exemption types
  are self-describing and should not carry stale basis text.

  This is a no-op when neither `vat_exemption_type` nor `vat_exemption_basis`
  is being changed, making it safe for use in global `changes do` blocks.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if relevant?(changeset) do
      case Ash.Changeset.get_attribute(changeset, :vat_exemption_type) do
        :other -> changeset
        _ -> Ash.Changeset.force_change_attribute(changeset, :vat_exemption_basis, nil)
      end
    else
      changeset
    end
  end

  @impl true
  def atomic(changeset, _opts, _context) do
    if relevant?(changeset) do
      {:atomic,
       %{
         vat_exemption_basis:
           expr(
             if ^atomic_ref(:vat_exemption_type) == :other,
               do: ^atomic_ref(:vat_exemption_basis)
           )
       }}
    else
      {:ok, changeset}
    end
  end

  defp relevant?(changeset) do
    Ash.Changeset.changing_attribute?(changeset, :vat_exemption_type) or
      Ash.Changeset.changing_attribute?(changeset, :vat_exemption_basis)
  end
end
