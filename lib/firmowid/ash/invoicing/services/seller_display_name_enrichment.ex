defmodule Firmowid.Ash.Invoicing.Services.SellerDisplayNameEnrichment do
  @moduledoc """
  Derives a stable seller display name for cost invoices from invoice contents.

  The derivation prefers exact historical matches by seller NIP and falls back
  to deterministic partial-name candidates from historical cost invoices.
  """

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage

  require Ash.Expr
  require Ash.Query
  require Logger

  @candidate_limit 20
  @max_history_scan 100
  @prompt_version 1

  @type candidate :: %{
          display_name: String.t(),
          seller: String.t() | nil,
          seller_nip: String.t() | nil
        }

  @spec generate_display_name(map(), keyword()) :: String.t() | nil
  def generate_display_name(document, opts \\ []) do
    seller = normalize_text(document[:seller] || document["seller"])
    seller_nip = normalize_tax_id(document[:seller_nip] || document["seller_nip"])
    items_list = normalize_items_list(document[:items_list] || document["items_list"])
    ash_opts = Keyword.get(opts, :ash_opts, [])
    current_cost_invoice_id = Keyword.get(opts, :current_cost_invoice_id)

    cond do
      is_nil(seller) ->
        nil

      exact_nip_candidate = exact_nip_candidate(seller_nip, current_cost_invoice_id, ash_opts) ->
        exact_nip_candidate

      true ->
        historical_candidates =
          historical_name_candidates(seller, current_cost_invoice_id, ash_opts)

        case exact_seller_candidate(seller, historical_candidates) do
          nil ->
            seller
            |> generate_via_llm(seller_nip, items_list, historical_candidates)
            |> normalize_generated_display_name(seller)

          display_name ->
            display_name
        end
    end
  end

  @spec exact_nip_candidate(String.t() | nil, Ash.UUID.t() | nil, keyword()) :: String.t() | nil
  defp exact_nip_candidate(nil, _current_cost_invoice_id, _ash_opts), do: nil

  defp exact_nip_candidate(seller_nip, current_cost_invoice_id, ash_opts) do
    seller_nip
    |> historical_candidates_query(current_cost_invoice_id, ash_opts)
    |> Ash.Query.filter(Ash.Expr.expr(seller_nip == ^seller_nip))
    |> Ash.Query.sort(inserted_at: :desc, seller_display_name: :asc, seller: :asc, id: :desc)
    |> Ash.Query.limit(@candidate_limit)
    |> Ash.read!(ash_opts)
    |> unique_candidates()
    |> List.first()
    |> case do
      %{display_name: display_name} -> display_name
      nil -> nil
    end
  end

  @spec historical_name_candidates(String.t(), Ash.UUID.t() | nil, keyword()) :: [candidate()]
  defp historical_name_candidates(seller, current_cost_invoice_id, ash_opts) do
    seller
    |> historical_candidates_query(current_cost_invoice_id, ash_opts)
    |> Ash.Query.filter(Ash.Expr.expr(contains(seller, ^seller) or contains(seller_display_name, ^seller)))
    |> Ash.Query.sort(inserted_at: :desc, seller_display_name: :asc, seller: :asc, id: :desc)
    |> Ash.Query.limit(@max_history_scan)
    |> Ash.read!(ash_opts)
    |> unique_candidates()
    |> Enum.take(@candidate_limit)
  end

  @spec historical_candidates_query(String.t() | nil, Ash.UUID.t() | nil, keyword()) ::
          Ash.Query.t()
  defp historical_candidates_query(_value, current_cost_invoice_id, ash_opts) do
    CostInvoice
    |> Ash.Query.for_read(:read, %{}, ash_opts)
    |> Ash.Query.select([:id, :seller, :seller_display_name, :seller_nip, :inserted_at])
    |> Ash.Query.filter(Ash.Expr.expr(not is_nil(seller_display_name) and seller_display_name != ""))
    |> maybe_exclude_current_invoice(current_cost_invoice_id)
  end

  defp maybe_exclude_current_invoice(query, nil), do: query

  defp maybe_exclude_current_invoice(query, current_cost_invoice_id) do
    Ash.Query.filter(query, Ash.Expr.expr(id != ^current_cost_invoice_id))
  end

  @spec unique_candidates([struct()]) :: [candidate()]
  defp unique_candidates(records) do
    {candidates, _seen} =
      Enum.reduce(records, {[], MapSet.new()}, fn record, {acc, seen} ->
        display_name = normalize_text(record.seller_display_name || record.seller)

        if is_nil(display_name) or MapSet.member?(seen, display_name) do
          {acc, seen}
        else
          candidate = %{
            display_name: display_name,
            seller: normalize_text(record.seller),
            seller_nip: normalize_tax_id(record.seller_nip)
          }

          {[candidate | acc], MapSet.put(seen, display_name)}
        end
      end)

    Enum.reverse(candidates)
  end

  @spec exact_seller_candidate(String.t(), [candidate()]) :: String.t() | nil
  defp exact_seller_candidate(seller, historical_candidates) do
    normalized_seller = normalize_comparison_text(seller)

    historical_candidates
    |> Enum.find(fn candidate ->
      normalize_comparison_text(candidate.seller) == normalized_seller
    end)
    |> case do
      %{display_name: display_name} -> display_name
      nil -> nil
    end
  end

  @spec generate_via_llm(String.t(), String.t() | nil, [map()], [candidate()]) :: String.t() | nil
  defp generate_via_llm(seller, seller_nip, items_list, historical_candidates) do
    openai = :firmowid |> Application.get_env(:openai_api_key) |> OpenaiEx.new()

    request =
      Chat.Completions.new(
        model: "gpt-5-nano",
        temperature: 0,
        max_completion_tokens: 300,
        reasoning_effort: "minimal",
        messages: [
          %{
            role: "developer",
            content: developer_prompt()
          },
          seller
          |> user_prompt(seller_nip, items_list, historical_candidates)
          |> ChatMessage.user()
        ]
      )

    response = Chat.Completions.create!(openai, request)

    response["choices"]
    |> List.first()
    |> Map.get("message")
    |> Map.get("content")
  rescue
    error ->
      Logger.warning("Failed to generate seller display name via OpenAI: #{inspect(error)}")
      nil
  end

  defp developer_prompt do
    String.trim("""
    Jesteś asystentem księgowym. Tworzysz krótką, czytelną nazwę wyświetlaną sprzedawcy
    dla faktur kosztowych.

    Zasady:
    - Zwróć wyłącznie jedną nazwę, bez cudzysłowów i bez komentarza.
    - Jeśli jedna z historycznych nazw pasuje do aktualnego sprzedawcy, zwróć dokładnie ją.
    - Preferuj nazwy krótsze od pełnej nazwy prawnej, ale nadal jednoznaczne dla człowieka.
    - Usuń zbędne formy prawne, jeśli nie są potrzebne do identyfikacji.
    - Jeśli brak dobrego historycznego dopasowania, utwórz najlepszą krótką nazwę z pełnej nazwy sprzedawcy.
    - Nie dodawaj informacji, których nie ma w danych wejściowych.
    """)
  end

  @spec user_prompt(String.t(), String.t() | nil, [map()], [candidate()]) :: String.t()
  defp user_prompt(seller, seller_nip, items_list, historical_candidates) do
    String.trim("""
    Wersja promptu: #{@prompt_version}

    Dane bieżącej faktury:
    - pełna nazwa sprzedawcy: #{seller}
    - NIP / tax id: #{seller_nip || "brak"}
    - pozycje faktury: #{inspect(Enum.take(items_list, 5))}

    Historyczne nazwy pasujące częściowo (maks. #{@candidate_limit}):
    #{format_candidates(historical_candidates)}

    Zwróć najlepszą jedną nazwę wyświetlaną sprzedawcy.
    """)
  end

  defp format_candidates([]), do: "- brak"

  defp format_candidates(candidates) do
    candidates
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {candidate, index} ->
      "- #{index}. display_name=#{candidate.display_name}; seller=#{candidate.seller || "brak"}; seller_nip=#{candidate.seller_nip || "brak"}"
    end)
  end

  @spec normalize_generated_display_name(String.t() | nil, String.t()) :: String.t()
  defp normalize_generated_display_name(nil, seller), do: seller

  defp normalize_generated_display_name(value, seller) do
    case value |> to_string() |> String.trim() |> String.trim("\"'") do
      "" -> seller
      normalized -> normalized
    end
  end

  @spec normalize_text(String.t() | nil) :: String.t() | nil
  defp normalize_text(nil), do: nil

  defp normalize_text(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      normalized -> normalized
    end
  end

  @spec normalize_comparison_text(String.t() | nil) :: String.t() | nil
  defp normalize_comparison_text(nil), do: nil

  defp normalize_comparison_text(value) do
    value
    |> normalize_text()
    |> case do
      nil ->
        nil

      normalized ->
        normalized
        |> String.downcase()
        |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
        |> String.trim()
    end
  end

  @spec normalize_tax_id(String.t() | nil) :: String.t() | nil
  defp normalize_tax_id(nil), do: nil

  defp normalize_tax_id(value) do
    value
    |> to_string()
    |> String.replace(~r/[^\p{N}A-Za-z]/u, "")
    |> String.upcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_items_list(items_list) when is_list(items_list), do: items_list
  defp normalize_items_list(_), do: []
end
