defmodule Firmowid.Ash.Invoicing.Validations.ValidateItemsNotEmpty do
  @moduledoc """
  Ash validation that ensures a list attribute or argument contains at least one element.

  Used on WizardDraft `:update_items` to prevent advancing with zero items,
  mirroring the `cast_assoc(:sales_invoice_items, required: true)` behavior
  from the legacy Ecto changeset.

  ## Options

    * `:field` — atom, the list to check (default: `:items`)
    * `:source` — `:attribute` or `:argument` (default: `:attribute`)
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    field = opts[:field] || :items
    source = opts[:source] || :attribute

    items =
      case source do
        :argument -> Ash.Changeset.get_argument(changeset, field)
        :attribute -> Ash.Changeset.get_attribute(changeset, field)
      end

    case items do
      items when is_list(items) and items != [] -> :ok
      _ -> {:error, field: field, message: "musi zawierać co najmniej jedną pozycję"}
    end
  end
end
