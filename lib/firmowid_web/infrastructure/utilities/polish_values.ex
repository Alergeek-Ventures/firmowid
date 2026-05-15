defmodule FirmowidWeb.Infrastructure.Utilities.PolishValues do
  @moduledoc """
  Shared parsers and encoders for Polish user-facing URL values.
  """

  @language_values %{"polski" => :pl, "angielski" => :en}
  @language_params Map.new(@language_values, fn {key, value} -> {value, key} end)

  @sort_order_values %{"rosnaco" => :asc, "malejaco" => :desc}
  @sort_order_params Map.new(@sort_order_values, fn {key, value} -> {value, key} end)

  @doc """
  Parses a Polish query value using the provided mapping.
  """
  @spec parse_atom(String.t() | nil, %{optional(String.t()) => atom() | boolean()}) ::
          atom() | boolean() | nil
  def parse_atom(raw_value, mapping) when is_binary(raw_value), do: Map.get(mapping, raw_value)
  def parse_atom(_raw_value, _mapping), do: nil

  @doc """
  Encodes a value into its Polish query representation using the provided mapping.
  """
  @spec encode_atom(atom() | boolean() | nil, %{optional(atom() | boolean()) => String.t()}) ::
          String.t() | nil
  def encode_atom(value, mapping), do: Map.get(mapping, value)

  @doc """
  Parses a Polish boolean query value.
  """
  @spec parse_boolean(String.t() | nil) :: boolean() | nil
  def parse_boolean(raw_value), do: parse_atom(raw_value, %{"tak" => true, "nie" => false})

  @doc """
  Encodes a boolean into a Polish query value.
  """
  @spec encode_boolean(boolean()) :: String.t()
  def encode_boolean(boolean) when is_boolean(boolean), do: encode_atom(boolean, %{true => "tak", false => "nie"})

  @doc """
  Parses a Polish language value.
  """
  @spec parse_language(String.t() | nil) :: :pl | :en | nil
  def parse_language(raw_value), do: parse_atom(raw_value, @language_values)

  @doc """
  Encodes a language atom into a Polish query value.
  """
  @spec encode_language(:pl | :en) :: String.t()
  def encode_language(language), do: encode_atom(language, @language_params)

  @doc """
  Parses a Polish sort-order value.
  """
  @spec parse_sort_order(String.t() | nil) :: :asc | :desc | nil
  def parse_sort_order(raw_value), do: parse_atom(raw_value, @sort_order_values)

  @doc """
  Encodes a sort-order atom into a Polish query value.
  """
  @spec encode_sort_order(:asc | :desc) :: String.t()
  def encode_sort_order(sort_order), do: encode_atom(sort_order, @sort_order_params)
end
