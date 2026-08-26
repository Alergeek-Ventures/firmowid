defmodule FirmowidWeb.Invoicing.Utilities.TransactionPresentation do
  @moduledoc """
  Interprets synced transaction data for presentation in the invoicing UI.

  Account ownership is preferred over the amount sign because imported logs can
  contain an amount whose sign does not agree with the debtor and creditor.
  """

  alias Firmowid.Ash.Finances.TransactionDirection

  @doc "Returns whether the transaction should be presented as income."
  @spec income?(map()) :: boolean()
  def income?(transaction), do: direction(transaction) == :income

  @doc "Returns the presentation direction of a transaction."
  @spec direction(map()) :: :income | :expense
  def direction(transaction), do: TransactionDirection.direction(transaction)

  @doc "Returns the transaction amount signed according to its presentation direction."
  @spec signed_amount(map()) :: Money.t()
  def signed_amount(transaction) do
    amount = transaction |> Map.fetch!(:amount) |> Money.abs()

    if income?(transaction), do: amount, else: Money.negate!(amount)
  end

  @doc """
  Returns the counterparty to display, falling back to a generic Polish label
  when imported party data is absent.
  """
  @spec counterparty_name(map()) :: String.t()
  def counterparty_name(transaction) do
    party_name =
      if income?(transaction),
        do: Map.get(transaction, :debtor_name),
        else: Map.get(transaction, :creditor_name)

    if present?(party_name) do
      party_name
    else
      "Transakcja bankowa"
    end
  end

  defp present?(value) when is_binary(value) do
    normalized =
      value
      |> String.replace(~r/\A\p{White_Space}+|\p{White_Space}+\z/u, "")
      |> String.upcase()

    normalized not in ["", "N/A"]
  end

  defp present?(_value), do: false
end
