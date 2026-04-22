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

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.Core.Nip
  alias Firmowid.Ash.Core.Pesel
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.IdentifierNormalization

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

    with :ok <- validate_pesel(pesel, pesel_field) do
      case CountryCodes.tax_id_type(country, pesel, type) do
        :nip -> validate_nip(tax_id, id_field)
        :eu_vat -> validate_eu_vat(tax_id, id_field)
        :optional_id -> validate_optional_id(tax_id, id_field)
        :other_id -> validate_optional_id(tax_id, id_field)
        :no_id -> :ok
      end
    end
  end

  @impl true
  def atomic(changeset, opts, _context) do
    id_field = opts[:id_field]
    country_field = opts[:country_field]
    pesel_field = opts[:pesel_field]
    type_field = opts[:type_field]

    fields = [id_field, country_field, pesel_field, type_field]

    if Enum.any?(changeset.action.arguments, &(&1.name in fields)) do
      validate(changeset, opts, %{})
    else
      atomic_rules(id_field, country_field, pesel_field, type_field)
    end
  end

  defp atomic_rules(id_field, country_field, pesel_field, type_field) do
    [
      invalid_pesel_rule(id_field, country_field, pesel_field, type_field),
      invalid_nip_rule(id_field, country_field, pesel_field, type_field),
      invalid_eu_vat_rule(id_field, country_field, pesel_field, type_field),
      invalid_optional_id_rule(id_field, country_field, pesel_field, type_field)
    ]
  end

  defp invalid_pesel_rule(id_field, country_field, pesel_field, type_field) do
    {:atomic, [id_field, country_field, pesel_field, type_field],
     expr(^present?(pesel_field) and not (^valid_pesel?(pesel_field))),
     expr(
       error(^InvalidAttribute, %{
         field: ^pesel_field,
         value: expr(^atomic_ref(pesel_field)),
         message: "musi być poprawnym numerem PESEL"
       })
     )}
  end

  defp invalid_nip_rule(id_field, country_field, pesel_field, type_field) do
    {:atomic, [id_field, country_field, pesel_field, type_field],
     expr(
       ^requires_nip?(country_field, pesel_field, type_field) and
         ^present?(id_field) and not (^valid_nip?(id_field))
     ),
     expr(
       error(^InvalidAttribute, %{
         field: ^id_field,
         value: expr(^atomic_ref(id_field)),
         message: "musi być poprawnym numerem NIP"
       })
     )}
  end

  defp invalid_eu_vat_rule(id_field, country_field, pesel_field, type_field) do
    {:atomic, [id_field, country_field, pesel_field, type_field],
     expr(
       ^requires_eu_vat?(country_field, pesel_field, type_field) and
         ^present?(id_field) and not (^valid_eu_vat?(id_field))
     ),
     expr(
       error(^InvalidAttribute, %{
         field: ^id_field,
         value: expr(^atomic_ref(id_field)),
         message: "musi być numerem VAT-EU"
       })
     )}
  end

  defp invalid_optional_id_rule(id_field, country_field, pesel_field, type_field) do
    {:atomic, [id_field, country_field, pesel_field, type_field],
     expr(
       (^requires_optional_id?(country_field, pesel_field, type_field) or
          ^requires_other_id?(country_field, pesel_field, type_field)) and
         ^present?(id_field) and string_length(^normalized_tax_id_ref(id_field)) > 50
     ),
     expr(
       error(^InvalidAttribute, %{
         field: ^id_field,
         value: expr(^atomic_ref(id_field)),
         message: "musi mieć maksymalnie 50 znaków"
       })
     )}
  end

  defp validate_nip(tax_id, field) when is_binary(tax_id) and tax_id != "" do
    if Nip.valid?(tax_id) do
      :ok
    else
      {:error, field: field, message: "musi być poprawnym numerem NIP"}
    end
  end

  defp validate_nip(_, _), do: :ok

  defp validate_pesel(pesel, field) when is_binary(pesel) and pesel != "" do
    if Pesel.valid?(pesel) do
      :ok
    else
      {:error, field: field, message: "musi być poprawnym numerem PESEL"}
    end
  end

  defp validate_pesel(_, _), do: :ok

  defp validate_eu_vat(tax_id, field) when is_binary(tax_id) and tax_id != "" do
    normalized_tax_id = IdentifierNormalization.normalize_tax_id(tax_id)

    if is_binary(normalized_tax_id) and
         Regex.match?(~r/^(\d|[A-Z]|\+|\*){1,12}$/, normalized_tax_id) do
      :ok
    else
      {:error, field: field, message: "musi być numerem VAT-EU"}
    end
  end

  defp validate_eu_vat(_, _), do: :ok

  defp validate_optional_id(tax_id, field) when is_binary(tax_id) and tax_id != "" do
    normalized_tax_id = IdentifierNormalization.normalize_tax_id(tax_id)

    if is_nil(normalized_tax_id) or String.length(normalized_tax_id) <= 50 do
      :ok
    else
      {:error, field: field, message: "musi mieć maksymalnie 50 znaków"}
    end
  end

  defp validate_optional_id(_, _), do: :ok

  defp present?(field) do
    expr(not is_nil(^atomic_ref(field)) and ^atomic_ref(field) != "")
  end

  defp no_id?(country_field, pesel_field, type_field) do
    expr(
      ^present?(pesel_field) or
        (^atomic_ref(type_field) == :individual and ^atomic_ref(country_field) == "PL")
    )
  end

  defp requires_nip?(country_field, pesel_field, type_field) do
    expr(not (^no_id?(country_field, pesel_field, type_field)) and ^atomic_ref(country_field) == "PL")
  end

  defp requires_eu_vat?(country_field, pesel_field, type_field) do
    expr(
      not (^no_id?(country_field, pesel_field, type_field)) and
        ^atomic_ref(country_field) in ^eu_countries() and ^atomic_ref(country_field) != "PL"
    )
  end

  defp requires_optional_id?(country_field, pesel_field, type_field) do
    expr(not (^no_id?(country_field, pesel_field, type_field)) and ^atomic_ref(country_field) == "US")
  end

  defp requires_other_id?(country_field, pesel_field, type_field) do
    expr(
      not (^no_id?(country_field, pesel_field, type_field)) and
        ^atomic_ref(country_field) not in ^(eu_countries() ++ ["US"])
    )
  end

  defp valid_eu_vat?(field) do
    expr(fragment("? ~ ?", ^normalized_tax_id_ref(field), ^~S/^(\d|[A-Z]|\+|\*){1,12}$/))
  end

  defp normalized_tax_id_ref(field) do
    expr(
      fragment(
        "regexp_replace(upper(coalesce(?, '')), '[^0-9A-Z\+\*]', '', 'g')",
        ^atomic_ref(field)
      )
    )
  end

  defp valid_nip?(field) do
    expr(
      fragment(
        """
        (CASE
          WHEN regexp_replace(?, '\\D', '', 'g') ~ '^[0-9]{10}$' THEN
            (((substring(regexp_replace(?, '\\D', '', 'g') from 1 for 1)::int * 6) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 2 for 1)::int * 5) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 3 for 1)::int * 7) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 4 for 1)::int * 2) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 5 for 1)::int * 3) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 6 for 1)::int * 4) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 7 for 1)::int * 5) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 8 for 1)::int * 6) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 9 for 1)::int * 7)) % 11) < 10
            AND
            (((substring(regexp_replace(?, '\\D', '', 'g') from 1 for 1)::int * 6) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 2 for 1)::int * 5) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 3 for 1)::int * 7) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 4 for 1)::int * 2) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 5 for 1)::int * 3) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 6 for 1)::int * 4) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 7 for 1)::int * 5) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 8 for 1)::int * 6) +
              (substring(regexp_replace(?, '\\D', '', 'g') from 9 for 1)::int * 7)) % 11) =
              substring(regexp_replace(?, '\\D', '', 'g') from 10 for 1)::int
          ELSE FALSE
        END)
        """,
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field)
      )
    )
  end

  defp valid_pesel?(field) do
    expr(
      fragment(
        """
        (CASE
          WHEN regexp_replace(?, '\\D', '', 'g') ~ '^[0-9]{11}$' THEN
            ((10 - (
              ((substring(regexp_replace(?, '\\D', '', 'g') from 1 for 1)::int * 1) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 2 for 1)::int * 3) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 3 for 1)::int * 7) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 4 for 1)::int * 9) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 5 for 1)::int * 1) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 6 for 1)::int * 3) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 7 for 1)::int * 7) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 8 for 1)::int * 9) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 9 for 1)::int * 1) +
               (substring(regexp_replace(?, '\\D', '', 'g') from 10 for 1)::int * 3)
              ) % 10)) % 10) = substring(regexp_replace(?, '\\D', '', 'g') from 11 for 1)::int
          ELSE FALSE
        END)
        """,
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field),
        ^atomic_ref(field)
      )
    )
  end

  defp eu_countries, do: CountryCodes.eu_countries_with_aliases()
end
