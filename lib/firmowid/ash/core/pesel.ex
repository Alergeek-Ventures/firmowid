defmodule Firmowid.Ash.Core.Pesel do
  @moduledoc """
  Utilities for validating Polish PESEL numbers.
  """

  @weights [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]

  @doc """
  Returns true when `pesel` is a valid 11-digit Polish PESEL.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(pesel) when is_binary(pesel) do
    with digits when byte_size(digits) == 11 <- normalize(pesel),
         true <- String.match?(digits, ~r/^\d{11}$/) do
      <<first_ten::binary-size(10), control::binary-size(1)>> = digits

      checksum =
        first_ten
        |> String.graphemes()
        |> Enum.map(&String.to_integer/1)
        |> Enum.zip(@weights)
        |> Enum.reduce(0, fn {digit, weight}, acc -> acc + digit * weight end)
        |> rem(10)
        |> then(fn value -> rem(10 - value, 10) end)

      checksum == String.to_integer(control)
    else
      _ -> false
    end
  end

  def valid?(_), do: false

  @doc """
  Canonicalizes a PESEL string to digits only, returning `nil` for blank input.
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(pesel) when is_binary(pesel) do
    case normalize_digits(pesel) do
      "" -> nil
      digits -> digits
    end
  end

  @doc """
  Normalizes a PESEL string by removing non-digit characters.
  """
  @spec normalize_digits(String.t()) :: String.t()
  def normalize_digits(pesel) when is_binary(pesel), do: String.replace(pesel, ~r/\D/, "")
end
