defmodule FirmowidWeb.Invoicing.FormHelpers do
  @moduledoc """
  Shared form-handling utilities for the invoicing UI.

  Provides common parsing and form-access helpers used across invoice editing
  views and components.
  """

  @doc """
  Parses a value into a `Decimal`, returning `nil` for blank or unparseable inputs.
  """
  @spec parse_decimal(term()) :: Decimal.t() | nil
  def parse_decimal(nil), do: nil
  def parse_decimal(""), do: nil
  def parse_decimal(%Decimal{} = d), do: d

  def parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {d, _} -> d
      :error -> nil
    end
  end

  def parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  def parse_decimal(value) when is_float(value), do: Decimal.from_float(value)
  def parse_decimal(_), do: nil

  @doc """
  Accesses nested forms from either a keyword list or map, defaulting to `[]`.
  """
  @spec access_forms(map() | keyword(), atom()) :: list()
  def access_forms(forms, key) when is_map(forms), do: Map.get(forms, key, [])
  def access_forms(forms, key) when is_list(forms), do: Keyword.get(forms, key, [])
end
