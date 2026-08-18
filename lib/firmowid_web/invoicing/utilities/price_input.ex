defmodule FirmowidWeb.Invoicing.Utilities.PriceInput do
  @moduledoc """
  Decimal helpers for invoice line-item gross price input.

  Sales invoice items persist `unit_price` as a net amount. These helpers allow
  forms to accept gross line totals while converting them to a high-precision net
  unit price before Ash validation/submission.
  """

  alias Firmowid.Ash.Ksef.VatRate

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

  @doc "Converts a gross line total to net unit price without currency-style rounding."
  @spec net_unit_price_from_gross_total(Decimal.t(), Decimal.t(), String.t() | nil) :: Decimal.t()
  def net_unit_price_from_gross_total(%Decimal{} = gross_total, %Decimal{} = quantity, vat_rate) do
    gross_total
    |> Decimal.div(quantity)
    |> net_unit_price_from_gross(vat_rate)
  end

  @doc "Converts nested line gross totals to net unit prices and strips UI-only fields."
  @spec normalize_gross_value_params(
          map(),
          String.t() | atom(),
          (term() -> Decimal.t() | nil),
          :all | MapSet.t()
        ) ::
          map()
  def normalize_gross_value_params(params, items_field, parse_decimal, indexes \\ :all) when is_map(params) do
    field = to_string(items_field)

    Map.update(params, field, %{}, &normalize_items(&1, parse_decimal, indexes))
  end

  @doc "Returns item indexes targeted by a gross-value form change."
  @spec gross_value_target_indexes(term(), String.t() | atom()) :: MapSet.t()
  def gross_value_target_indexes(target, items_field) when is_list(target) do
    field = to_string(items_field)

    target
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.reduce(MapSet.new(), fn
      [^field, index, "gross_value"], indexes -> MapSet.put(indexes, index)
      _chunk, indexes -> indexes
    end)
  end

  def gross_value_target_indexes(_target, _items_field), do: MapSet.new()

  @doc "Returns item indexes that submitted a gross-value field."
  @spec gross_value_param_indexes(map(), String.t() | atom()) :: MapSet.t()
  def gross_value_param_indexes(params, items_field) when is_map(params) do
    field = to_string(items_field)

    params
    |> Map.get(field, %{})
    |> case do
      items when is_map(items) ->
        MapSet.new(items, fn
          {index, %{} = item} -> if get_value(item, :gross_value), do: index
          {index, _item} -> index
        end)

      _items ->
        MapSet.new()
    end
    |> MapSet.delete(nil)
  end

  def gross_value_param_indexes(_params, _items_field), do: MapSet.new()

  defp normalize_items(items, parse_decimal, indexes) when is_map(items) do
    Map.new(items, fn {key, item} -> {key, normalize_item(key, item, parse_decimal, indexes)} end)
  end

  defp normalize_items(items, parse_decimal, indexes) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      normalize_item(to_string(index), item, parse_decimal, indexes)
    end)
  end

  defp normalize_items(items, _parse_decimal, _indexes), do: items

  defp normalize_item(index, item, parse_decimal, indexes) do
    if indexes == :all or MapSet.member?(indexes, index) do
      do_normalize_item(item, parse_decimal)
    else
      strip_gross_value(item)
    end
  end

  defp do_normalize_item(%{} = item, parse_decimal) do
    with gross_value when not is_nil(gross_value) <-
           item |> get_value(:gross_value) |> parse_decimal.(),
         quantity when not is_nil(quantity) <- item |> get_value(:quantity) |> parse_decimal.(),
         false <- Decimal.eq?(quantity, 0) do
      vat_rate = get_value(item, :vat_rate) || "0"

      item
      |> put_value(:unit_price, net_unit_price_from_gross_total(gross_value, quantity, vat_rate))
      |> strip_gross_value()
    else
      _ -> strip_gross_value(item)
    end
  end

  defp do_normalize_item(item, _parse_decimal), do: item

  defp strip_gross_value(%{} = item) do
    item
    |> Map.delete("gross_value")
    |> Map.delete(:gross_value)
  end

  defp get_value(map, key), do: Map.get(map, to_string(key)) || Map.get(map, key)

  defp put_value(map, key, value) do
    if Map.has_key?(map, to_string(key)) do
      Map.put(map, to_string(key), value)
    else
      Map.put(map, key, value)
    end
  end
end
