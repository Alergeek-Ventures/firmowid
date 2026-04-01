defmodule Firmowid.Ash.Finances.Preparations.ParadeDBSearch do
  @moduledoc """
  Applies ParadeDB full-text search to transactions when a `:query` argument is present.

  Uses the v2 `&&&` (conjunction) operator across debtor_name, creditor_name,
  remittance_information_unstructured, and transaction_currency. When a search
  query is present, results are sorted by `pdb.score()` relevance; otherwise
  the preparation is a no-op and the caller controls sorting.
  """
  use Ash.Resource.Preparation

  import Ash.Expr

  @impl true
  def prepare(query, _opts, _context) do
    case Ash.Query.get_argument(query, :query) do
      nil ->
        query

      "" ->
        query

      search_term ->
        Firmowid.Repo.put_paradedb_unnamed()

        # Hardcode column names in SQL — AshPostgres applies ::text casts to Ash
        # field references (e.g. `debtor_name` → `debtor_name::text`) which breaks
        # ParadeDB operators. Raw column names use the BM25 index directly.
        # Uses &&& (conjunction) so ALL ngrams from the search term must be present.
        # ||| (disjunction) is too loose with ngram(2,3) — matches on any single 2-char overlap.
        query
        |> Ash.Query.filter(
          fragment("debtor_name &&& ?", ^search_term) or
            fragment("creditor_name &&& ?", ^search_term) or
            fragment("remittance_information_unstructured &&& ?", ^search_term) or
            fragment("transaction_currency &&& ?", ^search_term)
        )
        |> Ash.Query.sort({calc(fragment("pdb.score(?)", id), type: :float), :desc})
    end
  end
end
