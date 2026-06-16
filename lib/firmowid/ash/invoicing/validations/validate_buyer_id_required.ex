defmodule Firmowid.Ash.Invoicing.Validations.ValidateBuyerIdRequired do
  @moduledoc """
  Ash validation that requires `buyer_id` when the buyer's tax ID type demands it.

  For KSeF compliance, Polish companies (`:nip`), EU VAT entities (`:eu_vat`),
  and other-ID entities (`:other_id`) must have a non-empty `buyer_id`.
  Only `:no_id` and `:optional_id` types may skip it.

  ## Options

    * `:id_field` — atom, the tax ID field (default: `:buyer_id`)
    * `:country_field` — atom (default: `:buyer_country`)
    * `:pesel_field` — atom (default: `:buyer_pesel`)
    * `:type_field` — atom, optional (default: `:buyer_type`)
  """
  use Ash.Resource.Validation

  alias Firmowid.Ash.Invoicing.CountryCodes

  @impl true
  def validate(changeset, opts, _context) do
    id_field = opts[:id_field] || :buyer_id
    id_type = resolve_id_type(changeset, opts)

    check_buyer_id(id_type, changeset, id_field)
  end

  defp resolve_id_type(changeset, opts) do
    country = Ash.Changeset.get_attribute(changeset, opts[:country_field] || :buyer_country)
    pesel = Ash.Changeset.get_attribute(changeset, opts[:pesel_field] || :buyer_pesel)
    type_field = opts[:type_field] || :buyer_type
    type = Ash.Changeset.get_attribute(changeset, type_field)

    CountryCodes.tax_id_type(country, pesel, type)
  end

  defp check_buyer_id(:no_id, _changeset, _id_field), do: :ok
  defp check_buyer_id(:optional_id, _changeset, _id_field), do: :ok

  defp check_buyer_id(_requires_id, changeset, id_field) do
    buyer_id = Ash.Changeset.get_attribute(changeset, id_field)

    if blank?(buyer_id) do
      {:error, field: id_field, message: "nie może być puste"}
    else
      :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
