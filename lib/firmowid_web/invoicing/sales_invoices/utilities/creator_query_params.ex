defmodule FirmowidWeb.Invoicing.SalesInvoices.Utilities.CreatorQueryParams do
  @moduledoc """
  Canonical parser and encoder for the sales invoice creator URL state.
  """

  alias FirmowidWeb.Infrastructure.Utilities.PolishValues
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams
  alias FirmowidWeb.Invoicing.Utilities.QueryCodec

  @creator_param_keys ~w(szkic_kreatora krok karta szukaj typ kolejnosc)

  @type query_params :: %{
          tab: QueryCodec.creator_tab(),
          search: String.t() | nil,
          filter: QueryCodec.counterparty_type() | nil,
          sort_order: :asc | :desc
        }

  @doc """
  Returns the allowlisted user-facing param keys for creator routes.
  """
  @spec param_keys() :: [String.t()]
  def param_keys, do: @creator_param_keys

  @doc """
  Parses the creator counterparty-step query state from raw route params.
  """
  @spec parse_query_params(map(), list()) :: query_params()
  def parse_query_params(params, last_counterparties) when is_map(params) and is_list(last_counterparties) do
    %{
      tab: parse_tab(params["karta"], last_counterparties),
      search: parse_search(params["szukaj"]),
      filter: QueryCodec.parse_counterparty_type(params["typ"]),
      sort_order: PolishValues.parse_sort_order(params["kolejnosc"]) || :asc
    }
  end

  @doc """
  Encodes typed creator query state into canonical query params.
  """
  @spec encode_query_params(query_params()) :: map()
  def encode_query_params(%{tab: tab, search: search, filter: filter, sort_order: sort_order}) do
    QueryParams.compact(%{
      karta: QueryCodec.encode_creator_tab(tab),
      szukaj: search,
      typ: QueryCodec.encode_counterparty_type(filter),
      kolejnosc: PolishValues.encode_sort_order(sort_order)
    })
  end

  @doc """
  Builds canonical creator route params for a draft step.
  """
  @spec draft_step_params(String.t(), integer()) :: map()
  def draft_step_params(creator_draft_id, step_number) when is_binary(creator_draft_id) and is_integer(step_number) do
    %{szkic_kreatora: creator_draft_id, krok: step_number}
  end

  @doc """
  Builds canonical creator route params for a draft step and query state.
  """
  @spec draft_step_params(String.t(), integer(), query_params()) :: map()
  def draft_step_params(creator_draft_id, step_number, query_params)
      when is_binary(creator_draft_id) and is_integer(step_number) and is_map(query_params) do
    Map.merge(draft_step_params(creator_draft_id, step_number), encode_query_params(query_params))
  end

  @doc """
  Normalizes raw creator route params into canonical string-keyed params.
  """
  @spec normalize_return_params(map()) :: {:ok, map()} | :error
  def normalize_return_params(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @creator_param_keys)),
         {:ok, creator_draft_id} <- parse_creator_draft_id(params),
         {:ok, step_number} <- parse_creator_step_number(params),
         {:ok, creator_tab} <- normalize_creator_tab_param(params),
         {:ok, search} <- normalize_search_param(params),
         {:ok, filter} <- normalize_filter_param(params),
         {:ok, sort_order} <- normalize_sort_order_param(params) do
      {:ok,
       QueryParams.compact(%{
         "szkic_kreatora" => creator_draft_id,
         "krok" => Integer.to_string(step_number),
         "karta" => creator_tab,
         "szukaj" => search,
         "typ" => filter,
         "kolejnosc" => sort_order
       })}
    else
      _error -> :error
    end
  end

  defp parse_tab(raw_tab, last_counterparties),
    do: QueryCodec.parse_creator_tab(raw_tab) || default_tab(last_counterparties)

  defp default_tab([]), do: :last_invoices
  defp default_tab(_last_counterparties), do: :last_counterparties

  defp parse_search(nil), do: nil
  defp parse_search(""), do: nil
  defp parse_search(value) when is_binary(value), do: value

  defp parse_creator_draft_id(%{"szkic_kreatora" => creator_draft_id})
       when is_binary(creator_draft_id) and creator_draft_id != "", do: {:ok, creator_draft_id}

  defp parse_creator_draft_id(_params), do: :error

  defp parse_creator_step_number(%{"krok" => raw_step_number}) when is_binary(raw_step_number) do
    case Integer.parse(raw_step_number) do
      {step_number, ""} when step_number in 1..4 -> {:ok, step_number}
      _error -> :error
    end
  end

  defp parse_creator_step_number(_params), do: :error

  defp normalize_creator_tab_param(%{"karta" => raw_creator_tab}) do
    case QueryCodec.parse_creator_tab(raw_creator_tab) do
      nil -> :error
      creator_tab -> {:ok, QueryCodec.encode_creator_tab(creator_tab)}
    end
  end

  defp normalize_creator_tab_param(_params), do: {:ok, nil}

  defp normalize_search_param(%{"szukaj" => search}) when is_binary(search), do: {:ok, search}
  defp normalize_search_param(_params), do: {:ok, nil}

  defp normalize_filter_param(%{"typ" => raw_filter}) do
    case QueryCodec.parse_counterparty_type(raw_filter) do
      nil -> :error
      filter -> {:ok, QueryCodec.encode_counterparty_type(filter)}
    end
  end

  defp normalize_filter_param(_params), do: {:ok, nil}

  defp normalize_sort_order_param(%{"kolejnosc" => raw_sort_order}) do
    case PolishValues.parse_sort_order(raw_sort_order) do
      nil -> :error
      sort_order -> {:ok, PolishValues.encode_sort_order(sort_order)}
    end
  end

  defp normalize_sort_order_param(_params), do: {:ok, nil}
end
