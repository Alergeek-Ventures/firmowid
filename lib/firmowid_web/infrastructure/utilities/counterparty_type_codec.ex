defmodule FirmowidWeb.Infrastructure.Utilities.CounterpartyTypeCodec do
  @moduledoc """
  Shared codec for user-facing counterparty type query values.
  """

  alias FirmowidWeb.Infrastructure.Utilities.PolishValues

  @values %{"firma" => :company, "osoba_fizyczna" => :individual}
  @params Map.new(@values, fn {key, value} -> {value, key} end)

  @type counterparty_type :: :company | :individual

  @doc """
  Parses the counterparty-type query value.
  """
  @spec parse(String.t() | nil) :: counterparty_type() | nil
  def parse(raw_value), do: PolishValues.parse_atom(raw_value, @values)

  @doc """
  Encodes the counterparty-type query value.
  """
  @spec encode(counterparty_type()) :: String.t()
  def encode(type), do: PolishValues.encode_atom(type, @params)
end
