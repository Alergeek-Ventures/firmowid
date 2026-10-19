defmodule Firmowid.Ash.Preparations.ParadeDBSearch do
  @moduledoc """
  Generic Ash preparation for ParadeDB full-text search.

  Applies BM25 search across configured columns when a search argument is
  present. When no search term is given, the preparation is a no-op.

  ## Options

    * `:columns` (required) — list of attribute names to search. They are passed as
      Ash references, so the generated SQL qualifies them with the table alias and
      stays unambiguous when the query joins related resources.

    * `:operator` — `:conjunction` (default) uses `&&&` (all ngrams must match),
      `:disjunction` uses `|||` (any ngram may match).

    * `:argument` — atom name of the search argument on the action.
      Defaults to `:query`.

  ## Example

      read :search do
        argument :query, :string

        prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
                 columns: ~w(name description)a, operator: :conjunction}
      end

  Automatically enables `prepare: :unnamed` on the repo (required for ParadeDB
  operators) and sorts results by `pdb.score()` relevance when a search term
  is active.
  """
  use Ash.Resource.Preparation

  import Ash.Expr

  @impl true
  def prepare(query, opts, _context) do
    columns = Keyword.fetch!(opts, :columns)
    operator = Keyword.get(opts, :operator, :conjunction)
    argument = Keyword.get(opts, :argument, :query)

    case Ash.Query.get_argument(query, argument) do
      nil ->
        query

      "" ->
        query

      search_term ->
        Firmowid.Repo.put_paradedb_unnamed()

        query
        |> Ash.Query.filter(^search_filter(columns, operator, search_term))
        |> Ash.Query.sort({calc(fragment("pdb.score(?)", id), type: :float), :desc})
    end
  end

  # A hit on ANY column is sufficient.
  defp search_filter(columns, operator, search_term) do
    columns
    |> Enum.map(&column_filter(&1, operator, search_term))
    |> Enum.reduce(&expr(^&2 or ^&1))
  end

  defp column_filter(column, :conjunction, search_term), do: expr(fragment("? &&& ?", ^ref(column), ^search_term))

  defp column_filter(column, :disjunction, search_term), do: expr(fragment("? ||| ?", ^ref(column), ^search_term))
end
