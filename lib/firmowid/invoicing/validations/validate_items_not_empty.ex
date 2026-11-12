defmodule Firmowid.Invoicing.Validations.ValidateItemsNotEmpty do
  @moduledoc """
  Ash validation that ensures a list attribute or argument contains at least one element.

  Used on WizardState `:update_items` to prevent advancing with zero items, and
  by `CompleteInvoice` to require sales invoice items.

  ## Options

    * `:field` — atom, the list to check (default: `:items`)
    * `:source` — `:attribute` or `:argument` (default: `:attribute`)
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

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
      _ -> {:error, field: field, message: gettext_noop("must contain at least one item")}
    end
  end
end
