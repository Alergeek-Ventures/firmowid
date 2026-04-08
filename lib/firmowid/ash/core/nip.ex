defmodule Firmowid.Ash.Core.Nip do
  @moduledoc """
  Utilities for validating Polish NIP numbers.
  """

  @weights [6, 5, 7, 2, 3, 4, 5, 6, 7]

  @doc """
  Returns true when `nip` is a valid 10-digit Polish NIP (checksum-aware).
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(nip) when is_binary(nip) do
    with digits when byte_size(digits) == 10 <- normalize_digits(nip),
         true <- String.match?(digits, ~r/^\d{10}$/) do
      <<first_nine::binary-size(9), control::binary-size(1)>> = digits

      checksum =
        first_nine
        |> String.graphemes()
        |> Enum.map(&String.to_integer/1)
        |> Enum.zip(@weights)
        |> Enum.reduce(0, fn {digit, weight}, acc -> acc + digit * weight end)
        |> rem(11)

      checksum < 10 and checksum == String.to_integer(control)
    else
      _ -> false
    end
  end

  def valid?(_), do: false

  @doc """
  Normalizes a NIP string by removing non-digit characters.
  """
  @spec normalize_digits(String.t()) :: String.t()
  def normalize_digits(nip) when is_binary(nip), do: String.replace(nip, ~r/\D/, "")
end
