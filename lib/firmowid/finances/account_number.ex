defmodule Firmowid.Finances.AccountNumber do
  @moduledoc """
  Compares bank account numbers written in different ways.

  Bank feeds and people write Polish accounts with or without the `PL` prefix, with spaces or
  dashes, so the key drops separators and the prefix of a Polish NRB.
  """

  @doc """
  Returns a key that is equal for two spellings of the same account number, or `nil` when there
  is no number.
  """
  @spec key(String.t() | nil) :: String.t() | nil
  def key(account) when is_binary(account) do
    account
    |> String.replace(~r/[^[:alnum:]]/, "")
    |> String.upcase()
    |> case do
      "" ->
        nil

      "NA" ->
        nil

      <<"PL", account::binary-size(26)>> = iban ->
        if String.match?(account, ~r/^\d{26}$/), do: account, else: iban

      iban ->
        iban
    end
  end

  def key(_account), do: nil
end
