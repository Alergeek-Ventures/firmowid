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

  defp blank_param?({_key, value}), do: blank_param?(value)
  defp blank_param?(nil), do: true
  defp blank_param?(""), do: true
  defp blank_param?([]), do: true
  defp blank_param?(_value), do: false
end
