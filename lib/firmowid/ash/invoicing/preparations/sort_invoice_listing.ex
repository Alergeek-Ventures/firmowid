defmodule Firmowid.Ash.Invoicing.Preparations.SortInvoiceListing do
  @moduledoc "Applies the shared date/id ordering used by bounded invoice cursor listings."

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    case Ash.Query.get_argument(query, :listing_sort) do
      nil ->
        query

      sort ->
        direction = if sort == :newest, do: :desc_nils_last, else: :asc_nils_last
        query |> Ash.Query.unset(:sort) |> Ash.Query.sort(issue_date: direction, id: :asc)
    end
  end
end
