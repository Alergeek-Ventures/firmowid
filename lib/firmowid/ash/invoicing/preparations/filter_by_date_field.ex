defmodule Firmowid.Ash.Invoicing.Preparations.FilterByDateField do
  @moduledoc """
  Preparation that filters by a configurable date field.

  Supports `date_field` argument values:
  - `:issue_date` — filter on `issue_date`
  - `:sale_date` — filter on `sale_date`
  - `:due_date` — filter on `due_date`
  - `:any` — OR filter on `issue_date` and `sale_date`

  Requires `date_from` and `date_to` arguments on the action.
  Skips filtering if neither date argument is provided.
  """
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    date_from = query.arguments[:date_from]
    date_to = query.arguments[:date_to]
    date_field = query.arguments[:date_field] || :issue_date

    if is_nil(date_from) and is_nil(date_to) do
      query
    else
      apply_date_filter(query, date_field, date_from, date_to)
    end
  end

  defp apply_date_filter(query, :any, date_from, date_to) do
    Ash.Query.filter_input(query, %{
      or: [
        [issue_date: date_bounds(date_from, date_to)],
        [sale_date: date_bounds(date_from, date_to)]
      ]
    })
  end

  defp apply_date_filter(query, field, date_from, date_to) when field in [:issue_date, :sale_date, :due_date] do
    Ash.Query.filter_input(query, %{field => date_bounds(date_from, date_to)})
  end

  defp date_bounds(nil, nil), do: %{}

  defp date_bounds(date_from, nil), do: %{greater_than_or_equal: date_from}

  defp date_bounds(nil, date_to), do: %{less_than_or_equal: date_to}

  defp date_bounds(date_from, date_to) do
    %{greater_than_or_equal: date_from, less_than_or_equal: date_to}
  end
end
