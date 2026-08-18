defmodule FirmowidWeb.Invoicing.Utilities.PriceInput do
  @moduledoc """
  Decimal helpers for invoice line-item price input modes.

  Sales invoice items persist `unit_price` as a net amount. These helpers allow
  forms to accept gross input while converting it to a high-precision net value
  before Ash validation/submission.
  """

  alias Firmowid.Ash.Ksef.VatRate

  @type mode :: :net | :gross

  @doc "Converts a submitted price mode into an atom."
  @spec parse_mode(term()) :: mode()
  def parse_mode(:gross), do: :gross
  def parse_mode("gross"), do: :gross
  def parse_mode(_), do: :net

  @doc "Returns the gross multiplier for a KSeF VAT rate code."
  @spec gross_multiplier(String.t() | nil) :: Decimal.t()
  def gross_multiplier(vat_rate) do
    vat_rate
    |> to_string()
    |> VatRate.to_numeric()
    |> Decimal.div(100)
    |> Decimal.add(1)
  end

  @doc "Converts a net unit price to gross for display."
  @spec gross_unit_price_from_net(Decimal.t(), String.t() | nil) :: Decimal.t()
  def gross_unit_price_from_net(%Decimal{} = net_unit_price, vat_rate) do
    Decimal.mult(net_unit_price, gross_multiplier(vat_rate))
  end

  @doc "Converts a gross unit price to net without currency-style rounding."
  @spec net_unit_price_from_gross(Decimal.t(), String.t() | nil) :: Decimal.t()
  def net_unit_price_from_gross(%Decimal{} = gross_unit_price, vat_rate) do
    Decimal.div(gross_unit_price, gross_multiplier(vat_rate))
  end

  @doc "Returns the form value to show for a persisted net unit price."
  @spec display_unit_price(Decimal.t() | nil, String.t() | nil, mode()) :: String.t() | nil
  def display_unit_price(nil, _vat_rate, _mode), do: nil

  def display_unit_price(%Decimal{} = unit_price, vat_rate, :gross) do
    unit_price
    |> gross_unit_price_from_net(vat_rate)
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  def display_unit_price(%Decimal{} = unit_price, _vat_rate, :net) do
    Decimal.to_string(unit_price, :normal)
  end

  @doc "Converts nested line-item params from gross unit price input to net unit price."
  @spec normalize_items_params(map(), String.t() | atom(), mode(), (term() -> Decimal.t() | nil)) ::
          map()
  def normalize_items_params(params, _items_field, :net, _parse_decimal), do: Map.delete(params, "price_input_mode")

  def normalize_items_params(params, items_field, :gross, parse_decimal) when is_map(params) do
    field = to_string(items_field)

    params
    |> Map.update(field, %{}, &normalize_items(&1, parse_decimal))
    |> Map.delete("price_input_mode")
  end

  defp normalize_items(items, parse_decimal) when is_map(items) do
    Map.new(items, fn {key, item} -> {key, normalize_item(item, parse_decimal)} end)
  end

  defp normalize_items(items, parse_decimal) when is_list(items), do: Enum.map(items, &normalize_item(&1, parse_decimal))

  defp normalize_items(items, _parse_decimal), do: items

  defp normalize_item(%{} = item, parse_decimal) do
    case item |> get_value(:unit_price) |> parse_decimal.() do
      gross_price when not is_nil(gross_price) ->
        vat_rate = get_value(item, :vat_rate) || "0"
        put_value(item, :unit_price, net_unit_price_from_gross(gross_price, vat_rate))

      _ ->
        item
    end
  end

  defp normalize_item(item, _parse_decimal), do: item

  defp get_value(map, key), do: Map.get(map, to_string(key)) || Map.get(map, key)

  defp put_value(map, key, value) do
    if Map.has_key?(map, to_string(key)) do
      Map.put(map, to_string(key), value)
    else
      Map.put(map, key, value)
    end
  end
end
