defmodule FirmowidWeb.Invoicing.Utilities.BankBadges do
  @moduledoc """
  Resolves bank badge variants for invoicing-related transaction views.
  """

  alias Firmowid.Ash.Finances.Transaction

  @badges_by_institution_id %{
    "SANDBOXFINANCE_SFIN0000" => "Default",
    "BANK_MILLENNIUM_BIGBPLPW" => "Millenium",
    "ING_PL_INGBPLPW" => "ING",
    "MBANK_CORPORATE_BREXPLPW" => "mBank",
    "MBANK_RETAIL_BREXPLPW" => "mBank",
    "NEST_BANK_CORPORATE_NESBPLPW" => "Nest Bank",
    "NEST_BANK_NESBPLPW" => "Nest Bank",
    "SANTANDER_PL_CORP_WBKPPLPP" => "Santander",
    "SANTANDER_PL_WBKPPLPP" => "Santander"
  }

  @doc """
  Returns the Figma bank badge variant for the given transaction.
  """
  @spec badge_for_transaction(Transaction.t()) :: String.t()
  def badge_for_transaction(%Transaction{bank_account: %{institution_id: institution_id}})
      when is_binary(institution_id) do
    Map.get(@badges_by_institution_id, String.trim(institution_id), "Default")
  end

  def badge_for_transaction(%Transaction{}), do: "Default"
end
