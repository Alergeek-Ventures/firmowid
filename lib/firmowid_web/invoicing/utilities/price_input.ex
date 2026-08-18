defmodule FirmowidWeb.Invoicing.Utilities.PriceInput do
  @moduledoc """
  Decimal helpers for invoice line-item gross price input.

  Sales invoice items persist `unit_price` as a net amount. These helpers allow
  forms to accept gross unit prices while converting them to a high-precision net
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

  @doc "Converts nested gross unit prices to net unit prices and strips UI-only fields."
  @spec normalize_gross_value_params(
          map(),
          String.t() | atom(),
          (term() -> Decimal.t() | nil),
          :all | MapSet.t()
        ) ::
          map()
  def normalize_gross_value_params(params, items_field, parse_decimal, indexes \\ :all) when is_map(params) do
    field = to_string(items_field)

    Map.update(params, field, %{}, fn items ->
      Map.new(items, fn {index, item} ->
        gross_value = Map.get(item, "gross_value") || Map.get(item, :gross_value)

        item =
          if indexes == :all or MapSet.member?(indexes, index) do
            case parse_decimal.(gross_value) do
              nil ->
                item

              gross_value ->
                vat_rate = Map.get(item, "vat_rate") || Map.get(item, :vat_rate) || "0"
                net_unit_price = net_unit_price_from_gross(gross_value, vat_rate)

                if Map.has_key?(item, "unit_price") do
                  Map.put(item, "unit_price", net_unit_price)
                else
                  Map.put(item, :unit_price, net_unit_price)
                end
            end
          else
            item
          end

        {index, Map.drop(item, ["gross_value", :gross_value])}
      end)
    end)
  end

  @doc "Returns item indexes whose gross price should be converted."
  @spec gross_value_indexes(map(), String.t() | atom(), term()) :: :all | MapSet.t()
  def gross_value_indexes(_params, _items_field, :all), do: :all

  def gross_value_indexes(params, items_field, target) do
    field = to_string(items_field)

    targeted_indexes =
      if is_list(target) do
        target
        |> Enum.chunk_every(3, 1, :discard)
        |> Enum.reduce(MapSet.new(), fn
          [^field, index, "gross_value"], indexes -> MapSet.put(indexes, index)
          _chunk, indexes -> indexes
        end)
      else
        MapSet.new()
      end

    submitted_indexes =
      params
      |> Map.get(field, %{})
      |> Enum.reduce(MapSet.new(), fn
        {index, %{} = item}, indexes when is_map_key(item, "gross_value") ->
          MapSet.put(indexes, index)

        _item, indexes ->
          indexes
      end)

    MapSet.union(targeted_indexes, submitted_indexes)
  end

  @doc "Updates transient gross line input values from submitted form params."
  @spec update_gross_value_inputs(map(), map(), String.t() | atom(), term()) :: map()
  def update_gross_value_inputs(gross_item_price_inputs, params, items_field, target) do
    field = to_string(items_field)

    submitted_values =
      params
      |> Map.get(field, %{})
      |> Enum.reduce(gross_item_price_inputs, fn
        {index, %{} = item}, inputs when is_map_key(item, "gross_value") ->
          Map.put(inputs, index, Map.fetch!(item, "gross_value"))

        _item, inputs ->
          inputs
      end)

    if is_list(target) do
      target
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.reduce(submitted_values, fn
        [^field, index, "unit_price"], inputs -> Map.delete(inputs, index)
        _chunk, inputs -> inputs
      end)
    else
      submitted_values
    end
  end
end
