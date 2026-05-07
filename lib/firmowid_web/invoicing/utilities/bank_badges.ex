defmodule FirmowidWeb.Invoicing.Utilities.BankBadges do
  @moduledoc """
  Resolves bank badge variants for invoicing-related transaction views.
  """

  alias Firmowid.Ash.Finances.Transaction

  @badge_candidates [
    "Alior Bank",
    "Millenium",
    "Pekao SA",
    "Paribas",
    "ING",
    "mBank",
    "mBank (firma)",
    "PKO BP",
    "Citi Bank",
    "Raiffeisen Bank",
    "Santander",
    "Velo Bank",
    "Credit Agricole",
    "Aion Bank",
    "Ebury",
    "Nest Bank",
    "Airwallex",
    "Erste",
    "Finom",
    "HSBC",
    "Ikano",
    "Inteligo",
    "Lunar",
    "Monese",
    "N26",
    "Neteller",
    "PayPal",
    "Paysera",
    "Revolut",
    "Skrill",
    "Soldo",
    "Stripe",
    "Vivid",
    "Wise"
  ]
  @badge_candidates_by_normalized_name Map.new(@badge_candidates, fn candidate ->
                                         {
                                           candidate
                                           |> String.trim()
                                           |> String.downcase()
                                           |> String.replace(~r/\s+/, "")
                                           |> String.replace(~r/[^a-z0-9]/u, ""),
                                           candidate
                                         }
                                       end)

  @badges_by_institution_id %{
    "SANDBOXFINANCE_SFIN0000" => "Default",
    "BANK_MILLENNIUM_BIGBPLPW" => "Millenium",
    "ING_PL_INGBPLPW" => "ING",
    "MBANK_CORPORATE_BREXPLPW" => "mBank (firma)",
    "MBANK_RETAIL_BREXPLPW" => "mBank (firma)",
    "NEST_BANK_CORPORATE_NESBPLPW" => "Nest Bank",
    "NEST_BANK_NESBPLPW" => "Nest Bank",
    "SANTANDER_PL_CORP_WBKPPLPP" => "Santander",
    "SANTANDER_PL_WBKPPLPP" => "Santander"
  }

  @badges_by_name_aliases %{
    "bankmillennium" => "Millenium",
    "bankpekao" => "Pekao SA",
    "bnpparibas" => "Paribas",
    "bnpparabiscorporate" => "Paribas",
    "erstepolska" => "Erste",
    "pkobankpolski" => "PKO BP",
    "pkobankpolskiipkobiznes" => "PKO BP",
    "mbank" => "mBank"
  }

  @badges_by_name_fragments %{
    "bankmillen" => "Millenium",
    "bankpekao" => "Pekao SA",
    "bnpparibas" => "Paribas",
    "pkobank" => "PKO BP",
    "mbank" => "mBank",
    "nestbank" => "Nest Bank",
    "erste" => "Erste",
    "airwallex" => "Airwallex"
  }

  @institution_badges_by_name_aliases Map.put(@badges_by_name_aliases, "mbank", "mBank (firma)")
  @institution_badges_by_name_fragments Map.put(
                                          @badges_by_name_fragments,
                                          "mbank",
                                          "mBank (firma)"
                                        )

  @doc """
  Returns the Figma bank badge variant for the given transaction.
  """
  @spec badge_for_transaction(Transaction.t()) :: String.t()
  def badge_for_transaction(%Transaction{bank_account: %{institution_id: institution_id}})
      when is_binary(institution_id) do
    badge_for_institution(institution_id)
  end

  def badge_for_transaction(%Transaction{bank_account: %{institution_name: institution_name}})
      when is_binary(institution_name) do
    badge_for_institution(%{name: institution_name})
  end

  def badge_for_transaction(%Transaction{}), do: "Default"

  @doc """
  Resolves the Figma bank badge variant from an institution reference.

  Accepted inputs:
  - `%{id: ..., name: ...}` or `%{institution_id: ..., institution_name: ...}`
  - string institution ID
  - plain bank label
  """
  @spec badge_for(map() | String.t() | nil) :: String.t()
  def badge_for(%Transaction{bank_account: bank_account}) when is_map(bank_account), do: badge_for(bank_account)

  def badge_for(%{institution_id: institution_id}) when is_binary(institution_id) do
    resolve_badge(%{id: institution_id})
  end

  def badge_for(%{id: id}) when is_binary(id) do
    resolve_badge(%{id: id})
  end

  def badge_for(%{institution_name: name}) when is_binary(name) do
    resolve_badge(%{name: name})
  end

  def badge_for(%{name: name}) when is_binary(name) do
    resolve_badge(%{name: name})
  end

  def badge_for(name) when is_binary(name) do
    resolve_badge(%{name: name})
  end

  def badge_for(nil), do: "Default"

  def badge_for(_), do: "Default"

  @doc """
  Resolves a bank badge from institution data.

  Unlike `badge_for/1`, this prefers institution-specific variants when a
  provider uses the same customer-facing bank name for a different visual badge.
  """
  @spec badge_for_institution(map() | String.t() | nil) :: String.t()
  def badge_for_institution(%Transaction{bank_account: bank_account}) when is_map(bank_account),
    do: badge_for_institution(bank_account)

  def badge_for_institution(%{institution_id: institution_id}) when is_binary(institution_id) do
    resolve_institution_badge(%{id: institution_id})
  end

  def badge_for_institution(%{id: id}) when is_binary(id) do
    resolve_institution_badge(%{id: id})
  end

  def badge_for_institution(%{institution_name: name}) when is_binary(name) do
    resolve_institution_badge(%{name: name})
  end

  def badge_for_institution(%{name: name}) when is_binary(name) do
    resolve_institution_badge(%{name: name})
  end

  def badge_for_institution(name) when is_binary(name) do
    resolve_institution_badge(%{id: name, name: name})
  end

  def badge_for_institution(nil), do: "Default"

  def badge_for_institution(_), do: "Default"

  defp resolve_badge(%{id: id}), do: id |> String.trim() |> resolve_id()

  defp resolve_badge(%{name: name}) when is_binary(name) do
    name
    |> normalize_bank_name()
    |> resolve_bank_name()
  end

  defp resolve_institution_badge(%{id: id, name: name}) when is_binary(id) and is_binary(name) do
    case id |> String.trim() |> resolve_id() do
      "Default" -> name |> normalize_bank_name() |> resolve_institution_name()
      badge -> badge
    end
  end

  defp resolve_institution_badge(%{id: id}), do: id |> String.trim() |> resolve_id()

  defp resolve_institution_badge(%{name: name}) when is_binary(name) do
    name
    |> normalize_bank_name()
    |> resolve_institution_name()
  end

  defp resolve_id(id) do
    case Map.get(@badges_by_institution_id, id, nil) do
      nil ->
        "Default"

      badge ->
        badge
    end
  end

  defp resolve_bank_name(name) do
    normalized = normalize_bank_name(name)

    cond do
      Map.has_key?(@badge_candidates_by_normalized_name, normalized) ->
        @badge_candidates_by_normalized_name[normalized]

      Map.has_key?(@badges_by_name_aliases, normalized) ->
        @badges_by_name_aliases[normalized]

      true ->
        resolve_by_fragment(normalized) || "Default"
    end
  end

  defp resolve_institution_name(normalized) do
    cond do
      normalized == "mbank" ->
        "mBank (firma)"

      Map.has_key?(@badge_candidates_by_normalized_name, normalized) and normalized != "mbank" ->
        @badge_candidates_by_normalized_name[normalized]

      Map.has_key?(@institution_badges_by_name_aliases, normalized) ->
        @institution_badges_by_name_aliases[normalized]

      true ->
        resolve_by_fragment(normalized, @institution_badges_by_name_fragments) || "Default"
    end
  end

  defp resolve_by_fragment(name, fragments \\ @badges_by_name_fragments) do
    Enum.find_value(fragments, fn {fragment, candidate} ->
      String.contains?(name, fragment) && candidate
    end)
  end

  defp normalize_bank_name(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "")
    |> String.replace(~r/[^a-z0-9]/u, "")
  end
end
