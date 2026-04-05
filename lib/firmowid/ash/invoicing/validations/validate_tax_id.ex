defmodule Firmowid.Ash.Invoicing.Validations.ValidateTaxId do
  @moduledoc """
  Ash validation that checks the tax ID format based on buyer context.

  Dispatches to NIP, EU VAT, or optional ID validation based on the
  `CountryCodes.tax_id_type/3` result.

  ## Options

    * `:id_field` — atom, the tax ID field (`:buyer_id` or `:tax_id`)
    * `:country_field` — atom (`:buyer_country` or `:country`)
    * `:pesel_field` — atom (`:buyer_pesel` or `:pesel`)
    * `:type_field` — atom, optional (`:buyer_type` or `:type`)
  """
  use Ash.Resource.Validation

  alias Firmowid.Ash.Invoicing.CountryCodes

  @impl true
  def validate(changeset, opts, _context) do
    id_field = opts[:id_field]
    country_field = opts[:country_field]
    pesel_field = opts[:pesel_field]
    type_field = opts[:type_field]

    country = Ash.Changeset.get_attribute(changeset, country_field)
    pesel = Ash.Changeset.get_attribute(changeset, pesel_field)
    type = if type_field, do: Ash.Changeset.get_attribute(changeset, type_field)
    tax_id = Ash.Changeset.get_attribute(changeset, id_field)

    case CountryCodes.tax_id_type(country, pesel, type) do
      :nip -> validate_nip(tax_id, id_field)
      :eu_vat -> validate_eu_vat(tax_id, id_field)
      :optional_id -> validate_optional_id(tax_id, id_field)
      :other_id -> validate_optional_id(tax_id, id_field)
      :no_id -> :ok
    end
  end

  defp validate_nip(tax_id, field) when is_binary(tax_id) and tax_id != "" do
    if Regex.match?(~r/^[1-9]((\d[1-9])|([1-9]\d))\d{7}$/, tax_id) do
      :ok
    else
      {:error, field: field, message: "musi być numerem NIP"}
    end
  end

  defp validate_nip(_, _), do: :ok

  defp validate_eu_vat(tax_id, field) when is_binary(tax_id) and tax_id != "" do
    if Regex.match?(~r/^(\d|[A-Z]|\+|\*){1,12}$/, tax_id) do
      :ok
    else
      {:error, field: field, message: "musi być numerem VAT-EU"}
    end
  end

  defp validate_eu_vat(_, _), do: :ok

  defp validate_optional_id(tax_id, field) when is_binary(tax_id) and tax_id != "" do
    if String.length(tax_id) <= 50 do
      :ok
    else
      {:error, field: field, message: "musi mieć maksymalnie 50 znaków"}
    end
  end

  defp validate_optional_id(_, _), do: :ok
end
