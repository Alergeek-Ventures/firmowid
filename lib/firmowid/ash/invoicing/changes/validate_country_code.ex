defmodule Firmowid.Ash.Invoicing.Changes.ValidateCountryCode do
  @moduledoc """
  Ash change that normalizes and validates an ISO country code field.

  Normalizes the value (uppercases, trims) and validates against the list of
  known ISO country codes. Skips nil values — allow_nil is handled by
  attribute constraints.

  ## Options

    * `:field` — atom, the attribute to validate (e.g. `:buyer_country`, `:country`)
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.CountryCodes

  @impl true
  def change(changeset, opts, _context) do
    field = opts[:field]

    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      value ->
        normalized = CountryCodes.normalize(value)

        changeset =
          if normalized == value do
            changeset
          else
            Ash.Changeset.force_change_attribute(changeset, field, normalized)
          end

        if CountryCodes.valid_country?(normalized) do
          changeset
        else
          Ash.Changeset.add_error(changeset,
            field: field,
            message: "musi być prawidłowym kodem ISO kraju"
          )
        end
    end
  end
end
