defmodule Firmowid.Ash.Preparations.ParadeDBSearch do
  @moduledoc """
  Generic Ash preparation for ParadeDB full-text search.

  Applies BM25 search across configured columns when a search argument is
  present. When no search term is given, the preparation is a no-op.

  ## Options

    * `:columns` (required) — list of raw SQL column name strings to search.
      Raw strings are used because AshPostgres applies `::text` casts to Ash
      field references, which breaks ParadeDB's `@@@`/`&&&`/`|||` operators.

    * `:operator` — `:conjunction` (default) uses `&&&` (all ngrams must match),
      `:disjunction` uses `|||` (any ngram may match).

    * `:argument` — atom name of the search argument on the action.
      Defaults to `:query`.

  ## Example

      read :search do
        argument :query, :string

        prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
                 columns: ~w(name description), operator: :conjunction}
      end

  Automatically enables `prepare: :unnamed` on the repo (required for ParadeDB
  operators) and sorts results by `pdb.score()` relevance when a search term
  is active.
  """
  use Ash.Resource.Preparation

  import Ash.Expr

  alias Ash.Query.Call

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

        op_str = operator_string(operator)

        query
        |> apply_column_filters(columns, op_str, search_term)
        |> Ash.Query.sort({calc(fragment("pdb.score(?)", id), type: :float), :desc})
    end
  end

  defp operator_string(:conjunction), do: "&&&"
  defp operator_string(:disjunction), do: "|||"

  # Builds an OR filter across all configured columns using raw SQL fragments.
  # Each column is matched independently — a hit on ANY column is sufficient.
  #
  # Column names are hardcoded strings in SQL to avoid AshPostgres `::text`
  # casts that break ParadeDB operators. We build `Ash.Query.Call` structs
  # directly because `fragment/2` is a compile-time macro and column names
  # are runtime configuration.
  defp apply_column_filters(query, columns, operator, search_term) do
    filter_expr =
      columns
      |> Enum.map(fn col ->
        %Call{
          name: :fragment,
          args: ["#{col} #{operator} ?", search_term],
          operator?: false,
          relationship_path: []
        }
      end)
      |> Enum.reduce(fn right, left ->
        %Ash.Query.BooleanExpression{op: :or, left: left, right: right}
      end)

    Ash.Query.filter(query, ^filter_expr)
  end
end
