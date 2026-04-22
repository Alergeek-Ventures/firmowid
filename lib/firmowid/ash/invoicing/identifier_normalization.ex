defmodule Firmowid.Ash.Invoicing.IdentifierNormalization do
  @moduledoc """
  Canonical runtime normalization for invoice/counterparty identifiers.
  """

  alias Firmowid.Ash.Core.Pesel
  alias Firmowid.Ash.Invoicing.TaxId

  @doc """
  Normalizes tax identifiers for matching and storage comparisons.
  """
  @spec normalize_tax_id(String.t() | nil) :: String.t() | nil
  def normalize_tax_id(value), do: TaxId.normalize(value)

  @doc """
  Normalizes PESEL values for matching and comparisons.
  """
  @spec normalize_pesel(String.t() | nil) :: String.t() | nil
  def normalize_pesel(value), do: Pesel.normalize(value)
end
