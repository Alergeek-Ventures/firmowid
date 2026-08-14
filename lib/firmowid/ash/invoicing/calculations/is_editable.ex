defmodule Firmowid.Ash.Invoicing.Calculations.IsEditable do
  @moduledoc """
  Determines whether a sales invoice can be edited.

  Module calc because the KOR case requires self-referential relationship
  traversal: checking if this correction is the latest among its parent's
  corrections. Cannot be expressed in pure `expr()`.

  Rules:
   1. KOR → true only if this is the latest correction of the corrected invoice
   2. VAT with corrections → false
   3. Draft (no invoice_number) → true
   4. Not locked → true
   5. Otherwise → false
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:corrections, corrected_invoice: :corrections]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &editable?/1)
  end

  defp editable?(%{ksef_invoice_kind: :kor, corrected_invoice: %{corrections: corrections}} = invoice)
       when is_list(corrections) do
    case List.last(corrections) do
      nil -> false
      latest -> latest.id == invoice.id
    end
  end

  defp editable?(%{ksef_invoice_kind: :vat, corrections: corrections}) when is_list(corrections) do
    Enum.empty?(corrections)
  end

  defp editable?(%{invoice_number: nil}), do: true
  defp editable?(%{locked_at: nil}), do: true
  defp editable?(%{}), do: false
end
