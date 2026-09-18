defmodule FirmowidWeb.Infrastructure.Utilities.QueryParams do
  @moduledoc """
  Shared helpers for parsing and encoding user-facing query params.
  """

  @doc """
  Removes blank query values while preserving explicit booleans.
  """
  @spec compact(map() | keyword()) :: map() | keyword()
  def compact(params) when is_map(params) do
    Map.reject(params, &blank_param?/1)
  end

  def compact(params) when is_list(params) do
    Enum.reject(params, &blank_param?/1)
  end

  @doc """
  Parses an ISO8601 date from a query map, returning a default when absent or invalid.
  """
  @spec parse_date(map(), String.t(), Date.t() | nil) :: Date.t() | nil
  def parse_date(params, key, default) do
    case Map.get(params, key) do
      nil ->
        default

      date_string ->
        case Date.from_iso8601(date_string) do
          {:ok, parsed_date} -> parsed_date
          _error -> default
        end
    end
  end

  @doc """
  Parses an integer from a query map, returning a default when absent or invalid.
  """
  @spec parse_integer(map(), String.t(), integer() | nil) :: integer() | nil
  def parse_integer(params, key, default) do
    case Map.get(params, key) do
      nil ->
        default

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed_integer, ""} -> parsed_integer
          _error -> default
        end

      _value ->
        default
    end
  end

  @doc """
  Filters a query map down to allowlisted string keys.
  """
  @spec take_allowed_params(map(), [String.t()], %{String.t() => atom()}) :: map()
  def take_allowed_params(params, allowed_keys, param_atom_keys)
      when is_map(params) and is_list(allowed_keys) and is_map(param_atom_keys) do
    Enum.reduce(allowed_keys, %{}, fn key, filtered_params ->
      atom_key = Map.fetch!(param_atom_keys, key)

      cond do
        Map.has_key?(params, key) ->
          Map.put(filtered_params, key, Map.fetch!(params, key))

        Map.has_key?(params, atom_key) ->
          Map.put(filtered_params, key, Map.fetch!(params, atom_key))

        true ->
          filtered_params
      end
    end)
  end

  defp blank_param?({_key, value}), do: blank_param?(value)
  defp blank_param?(nil), do: true
  defp blank_param?(""), do: true
  defp blank_param?([]), do: true
  defp blank_param?(_value), do: false
end
