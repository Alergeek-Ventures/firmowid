defmodule Firmowid.Ash.Invoicing.Validations.ValidateItemsNotEmpty do
  @moduledoc """
  Ash validation that ensures a list attribute or argument contains at least one element.

  Used on WizardDraft `:update_items` to prevent advancing with zero items,
  mirroring the `cast_assoc(:sales_invoice_items, required: true)` behavior
  from the legacy Ecto changeset.

  On `:argument` sources, "not supplied" and "supplied empty" are distinct
  states: `Ash.Changeset.fetch_argument/2` returns `:error` when the caller
  never passed the list. `:require_argument?` decides whether that absence is
  a violation or simply means the action does not touch the list.

  ## Options

    * `:field` — atom, the list to check (default: `:items`)
    * `:source` — `:attribute` or `:argument` (default: `:attribute`)
    * `:require_argument?` — boolean, `:argument` sources only. When `false`, a
      missing argument passes validation. Defaults to `true`.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    field = opts[:field] || :items
    source = opts[:source] || :attribute

    case source do
      :argument -> validate_argument(changeset, field, opts)
      :attribute -> changeset |> Ash.Changeset.get_attribute(field) |> check_items(field)
    end
  end

  defp validate_argument(changeset, field, opts) do
    case Ash.Changeset.fetch_argument(changeset, field) do
      :error -> if opts[:require_argument?] == false, do: :ok, else: empty_error(field)
      {:ok, items} -> check_items(items, field)
    end
  end

  defp check_items(items, field) do
    case items do
      items when is_list(items) and items != [] -> :ok
      _ -> empty_error(field)
    end
  end

  defp empty_error(field) do
    {:error, field: field, message: "musi zawierać co najmniej jedną pozycję"}
  end
end
