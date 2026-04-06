defmodule Firmowid.Ash.Core.ContractType do
  @moduledoc """
  Employment contract type enum helpers.

  Provides human-readable titles and helper functions for the
  `employment_contract_type` enum field on User.
  """

  @titles %{
    umowa_o_prace: "Umowa o pracę",
    umowa_zlecenie: "Umowa zlecenie",
    umowa_o_dzielo: "Umowa o dzieło",
    b2b: "B2B"
  }

  @doc """
  Returns the list of valid contract type atoms.

  ## Examples

      iex> Firmowid.Ash.Core.ContractType.values()
      [:umowa_o_prace, :umowa_zlecenie, :umowa_o_dzielo, :b2b]
  """
  def values, do: Map.keys(@titles)

  @doc """
  Returns the human-readable title for a contract type.

  ## Examples

      iex> Firmowid.Ash.Core.ContractType.title(:umowa_o_prace)
      "Umowa o pracę"

      iex> Firmowid.Ash.Core.ContractType.title(nil)
      nil
  """
  def title(nil), do: nil
  def title(type) when is_atom(type), do: Map.fetch!(@titles, type)

  @doc """
  Returns options suitable for Phoenix form select inputs.

  ## Examples

      iex> Firmowid.Ash.Core.ContractType.options_for_select()
      [{"Umowa o pracę", :umowa_o_prace}, {"Umowa zlecenie", :umowa_zlecenie}, ...]
  """
  def options_for_select, do: Enum.map(@titles, fn {k, v} -> {v, k} end)
end
