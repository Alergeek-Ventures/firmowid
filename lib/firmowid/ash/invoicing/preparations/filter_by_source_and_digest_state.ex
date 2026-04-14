defmodule Firmowid.Ash.Invoicing.Preparations.FilterBySourceAndDigestState do
  @moduledoc """
  Preparation that applies source and digest-membership filters for cost invoices.

  Supported action arguments:
  - `source`: `nil | :manual_import | :ksef` (nil means no filtering)
  - `in_digest`: `nil | :yes | :no` (nil means no filtering)
  """
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    query
    |> apply_source_filter(query.arguments[:source])
    |> apply_digest_filter(query.arguments[:in_digest])
  end

  defp apply_source_filter(query, nil), do: query
  defp apply_source_filter(query, :ksef), do: Ash.Query.filter(query, is_ksef_imported == true)

  defp apply_source_filter(query, :manual_import), do: Ash.Query.filter(query, is_ksef_imported == false)

  defp apply_digest_filter(query, nil), do: query
  defp apply_digest_filter(query, :yes), do: Ash.Query.filter(query, is_in_ksef_digest == true)
  defp apply_digest_filter(query, :no), do: Ash.Query.filter(query, is_in_ksef_digest == false)
end
