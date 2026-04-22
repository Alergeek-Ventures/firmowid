defmodule Firmowid.Ash.Invoicing.Changes.NormalizeCounterpartyTaxId do
  @moduledoc """
  Stores the canonical counterparty tax ID used for uniqueness checks.
  """

  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.TaxId

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(
      changeset,
      :normalized_tax_id,
      TaxId.normalize(Ash.Changeset.get_attribute(changeset, :tax_id))
    )
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic,
     %{
       normalized_tax_id:
         expr(
           cond do
             is_nil(^atomic_ref(:tax_id)) ->
               nil

             string_trim(^atomic_ref(:tax_id)) == "" ->
               nil

             true ->
               fragment(
                 "nullif(regexp_replace(upper(coalesce(?, '')), '[^0-9A-Z]', '', 'g'), '')",
                 ^atomic_ref(:tax_id)
               )
           end
         )
     }}
  end
end
