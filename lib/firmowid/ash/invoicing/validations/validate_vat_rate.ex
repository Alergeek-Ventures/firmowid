defmodule Firmowid.Ash.Invoicing.Validations.ValidateVatRate do
  @moduledoc """
  Ash validation that checks a VAT rate against the list of valid KSeF codes.

  ## Options

    * `:field` — atom, the field to validate (default: `:vat_rate`)
  """
  use Ash.Resource.Validation

  alias Firmowid.Ksef.VatRate

  @impl true
  def validate(changeset, opts, _context) do
    field = opts[:field] || :vat_rate
    value = Ash.Changeset.get_attribute(changeset, field)

    cond do
      is_nil(value) ->
        :ok

      VatRate.valid?(value) ->
        :ok

      true ->
        {:error, field: field, message: "nieprawidłowa stawka VAT"}
    end
  end
end
