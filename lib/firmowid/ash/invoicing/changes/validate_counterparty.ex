defmodule Firmowid.Ash.Invoicing.Changes.ValidateCounterparty do
  @moduledoc """
  Ash change that applies counterparty-specific validations:

  - Normalizes and validates country codes (`:country`, `:mail_country`)
  - Validates tax ID based on country/PESEL (NIP, EU VAT, optional)
  - Validates name fields based on type (company → full_name, individual → given_name + surname)
  - Clears irrelevant fields based on type switch
  """
  use Ash.Resource.Change

  alias Firmowid.SalesInvoices.CountryCodes

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> validate_country_code(:country)
    |> validate_country_code(:mail_country)
    |> validate_tax_id()
    |> validate_name_fields()
    |> cast_based_on_type()
  end

  defp validate_country_code(changeset, field) do
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

  defp validate_tax_id(changeset) do
    country = Ash.Changeset.get_attribute(changeset, :country)
    pesel = Ash.Changeset.get_attribute(changeset, :pesel)
    tax_id = Ash.Changeset.get_attribute(changeset, :tax_id)

    case CountryCodes.tax_id_type(country, pesel) do
      :nip -> validate_nip(changeset, tax_id)
      :eu_vat -> validate_eu_vat(changeset, tax_id)
      _ -> validate_optional_id(changeset, tax_id)
    end
  end

  defp validate_nip(changeset, tax_id) when is_binary(tax_id) do
    if Regex.match?(~r/^[1-9]((\d[1-9])|([1-9]\d))\d{7}$/, tax_id) do
      changeset
    else
      Ash.Changeset.add_error(changeset, field: :tax_id, message: "musi być numerem NIP")
    end
  end

  defp validate_nip(changeset, _), do: changeset

  defp validate_eu_vat(changeset, tax_id) when is_binary(tax_id) do
    if Regex.match?(~r/^(\d|[A-Z]|\+|\*){1,12}$/, tax_id) do
      changeset
    else
      Ash.Changeset.add_error(changeset, field: :tax_id, message: "musi być numerem VAT-EU")
    end
  end

  defp validate_eu_vat(changeset, _), do: changeset

  defp validate_optional_id(changeset, tax_id) when is_binary(tax_id) do
    if String.length(tax_id) <= 50 do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :tax_id,
        message: "musi mieć maksymalnie 50 znaków"
      )
    end
  end

  defp validate_optional_id(changeset, _), do: changeset

  defp validate_name_fields(changeset) do
    type = Ash.Changeset.get_attribute(changeset, :type)

    case type do
      :company ->
        full_name = Ash.Changeset.get_attribute(changeset, :full_name)

        if is_nil(full_name) or full_name == "" do
          Ash.Changeset.add_error(changeset,
            field: :full_name,
            message: "nazwa firmy jest wymagana"
          )
        else
          changeset
        end

      :individual ->
        changeset
        |> validate_required_field(:given_name, "imię jest wymagane")
        |> validate_required_field(:surname, "nazwisko jest wymagane")

      _ ->
        changeset
    end
  end

  defp validate_required_field(changeset, field, message) do
    value = Ash.Changeset.get_attribute(changeset, field)

    if is_nil(value) or value == "" do
      Ash.Changeset.add_error(changeset, field: field, message: message)
    else
      changeset
    end
  end

  defp cast_based_on_type(changeset) do
    case Ash.Changeset.get_attribute(changeset, :type) do
      :individual ->
        changeset
        |> Ash.Changeset.force_change_attribute(:tax_id, "")
        |> Ash.Changeset.force_change_attribute(:full_name, nil)

      :company ->
        changeset
        |> Ash.Changeset.force_change_attribute(:pesel, nil)
        |> Ash.Changeset.force_change_attribute(:given_name, nil)
        |> Ash.Changeset.force_change_attribute(:surname, nil)

      _ ->
        changeset
    end
  end
end
