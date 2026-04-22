defmodule Firmowid.Ash.Invoicing.Preparations.CounterpartySearchSort do
  @moduledoc """
  Applies default sorting to counterparty search results when no ParadeDB
  search term is active.

  When a search term is present, `ParadeDBSearch` preparation handles sorting
  by `pdb.score()` relevance. This preparation only applies when there is no
  search term, sorting by `:sort_by` and `:sort_order` arguments.
  """
  use Ash.Resource.Preparation

  import Ash.Expr

  @impl true
  def prepare(query, _opts, _context) do
    search_term = Ash.Query.get_argument(query, :search)

    if search_term in [nil, ""] do
      sort_by = Ash.Query.get_argument(query, :sort_by) || :name
      sort_order = Ash.Query.get_argument(query, :sort_order) || :asc

      apply_sorting(query, sort_by, sort_order)
    else
      query
    end
  end

  defp apply_sorting(query, :name, order) do
    Ash.Query.sort(query, [
      {calc(fragment("COALESCE(?, ?, ?)", display_name, full_name, surname), type: :string), order}
    ])
  end

  defp apply_sorting(query, :display_name, order) do
    Ash.Query.sort(query, [
      {calc(fragment("COALESCE(?, ?, ?)", display_name, full_name, given_name), type: :string), order}
    ])
  end

  defp apply_sorting(query, :created_at, order) do
    Ash.Query.sort(query, [{:inserted_at, order}])
  end

  defp apply_sorting(query, _sort_by, order) do
    apply_sorting(query, :name, order)
  end
end
