defmodule Firmowid.Ash.Invoicing.TaxId do
  @moduledoc """
  Utilities for canonical tax identifier normalization.
  """

  @doc """
  Normalizes a tax identifier by uppercasing it and removing non-alphanumeric
  characters.
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(value) do
    value
    |> to_string()
    |> String.replace(~r/[^\p{N}A-Za-z]/u, "")
    |> String.upcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end
end
