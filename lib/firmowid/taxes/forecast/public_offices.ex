defmodule Firmowid.Taxes.Forecast.PublicOffices do
  @moduledoc """
  Recognizes the public offices that send money to a company by the name a bank
  writes on the transfer: a tax office and ZUS, in any letter case and with or
  without Polish diacritics.
  """

  @doc "Returns whether the name is a tax office's (\"Urząd Skarbowy\")."
  @spec tax_office?(String.t() | nil) :: boolean()
  def tax_office?(name), do: String.contains?(plain(name), "urzad skarbowy")

  @doc "Returns whether the name is ZUS's (\"Zakład Ubezpieczeń Społecznych\" or its abbreviation)."
  @spec zus?(String.t() | nil) :: boolean()
  def zus?(name) do
    name = plain(name)
    String.contains?(name, "zaklad ubezpieczen spolecznych") or Regex.match?(~r/\bzus\b/, name)
  end

  @doc "Returns the text in lowercase without diacritics; a missing one is empty."
  @spec plain(String.t() | nil) :: String.t()
  def plain(nil), do: ""

  # ł has no decomposition.
  def plain(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("ł", "l")
  end
end
