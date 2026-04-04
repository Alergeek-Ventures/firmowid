defmodule Firmowid.Ash.Invoicing.Validations.ValidateItemsNotEmpty do
  @moduledoc """
  Ash validation that ensures a list attribute contains at least one element.

  Used on WizardDraft `:update_items` to prevent advancing with zero items,
  mirroring the `cast_assoc(:sales_invoice_items, required: true)` behavior
  from the legacy Ecto changeset.

  ## Options

    * `:field` — atom, the list attribute to check (default: `:items`)
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    field = opts[:field] || :items

    case Ash.Changeset.get_attribute(changeset, field) do
      items when is_list(items) and items != [] -> :ok
      _ -> {:error, field: field, message: "musi zawierać co najmniej jedną pozycję"}
    end
  end
end
