defmodule Firmowid.Ash.Expressions.ParadeDBSearch do
  @moduledoc """
  Custom Ash expression for ParadeDB full-text search via the `@@@` operator.

  Usage in Ash filters:

      Ash.Query.filter(Project, paradedb_search(name, ^search_term))

  **Note on `::text` casts:** AshPostgres type-casts attribute references in
  fragments (e.g. `name` → `name::text`). ParadeDB's `@@@` operator is
  incompatible with type casts — it needs the raw column reference to use the
  BM25 index. This expression uses `:any` for the field argument type to
  minimise casting. If a `::text` cast is still applied at runtime, use the
  fragment directly instead: `fragment("name @@@ ?", ^search)`.

  Requires `prepare: :unnamed` repo option — call `Repo.put_paradedb_unnamed/0`
  before queries that use this expression. See `Firmowid.Repo` for details.
  """
  use Ash.CustomExpression,
    name: :paradedb_search,
    arguments: [[:any, :string]]

  @doc false
  def expression(AshPostgres.DataLayer, [field, query]) do
    {:ok, expr(fragment("? @@@ ?", ^field, ^query))}
  end

  def expression(_data_layer, _args), do: :unknown
end
