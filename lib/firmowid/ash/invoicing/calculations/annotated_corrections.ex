defmodule Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections do
  @moduledoc """
  Returns the corrections list with each correction annotated with its
  `reference_invoice` — the "before" state for that correction.

  Corrections are sorted by timestamp (locked_at/inserted_at).
  Each correction's `reference_invoice` is the previous correction in order,
  or the original VAT invoice for the first correction.

  Pure — no internal `Ash.load!` calls.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:corrections, corrections: :sales_invoice_items]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &annotate/1)
  end

  @doc """
  Annotates corrections with reference_invoice and corrected_invoice.

  Can be called directly when corrections are already loaded to avoid
  Ash.load! re-fetching relationships (which may lose attribute selection).
  """
  def annotate(%{corrections: corrections} = invoice) when is_list(corrections) do
    sorted = Enum.sort_by(corrections, &safe_timestamp/1, DateTime)
    references = [invoice | sorted]

    [sorted, references]
    |> Enum.zip()
    |> Enum.map(fn {correction, reference} ->
      correction
      |> Map.put(:reference_invoice, reference)
      |> Map.put(:corrected_invoice, invoice)
    end)
  end

  def annotate(_), do: []

  defp safe_timestamp(record) do
    case {record.locked_at, record.inserted_at} do
      {%DateTime{} = ts, _} -> ts
      {_, %DateTime{} = ts} -> ts
      _ -> ~U[1970-01-01 00:00:00Z]
    end
  end
end
