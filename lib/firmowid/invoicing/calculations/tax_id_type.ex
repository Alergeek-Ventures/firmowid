defmodule Firmowid.Invoicing.Calculations.TaxIdType do
  @moduledoc """
  Tax ID type of a party (`:nip | :eu_vat | :other_id | :optional_id | :no_id`) derived
  from its PESEL, type and country. Reads the `buyer_*` fields unless the `pesel`, `type`
  and `country` options name others.

  An expression, so data layers can evaluate it without loading records.
  Runtime equivalent: `Firmowid.Invoicing.CountryCodes.tax_id_type/3`.
  """
  use Ash.Resource.Calculation

  alias Firmowid.Invoicing.CountryCodes

  @eu_countries CountryCodes.eu_countries_with_aliases()

  @impl true
  def init(opts), do: Keyword.validate(opts, pesel: :buyer_pesel, type: :buyer_type, country: :buyer_country)

  @impl true
  def expression(opts, _context) do
    expr(
      cond do
        not is_nil(^ref(opts[:pesel])) and ^ref(opts[:pesel]) != "" -> :no_id
        ^ref(opts[:type]) == :individual and ^ref(opts[:country]) == "PL" -> :no_id
        ^ref(opts[:country]) == "PL" -> :nip
        ^ref(opts[:country]) in ^@eu_countries -> :eu_vat
        ^ref(opts[:country]) == "US" -> :optional_id
        true -> :other_id
      end
    )
  end
end
