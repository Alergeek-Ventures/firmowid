defmodule FirmowidWeb.Delegations.Utilities.SettlementDocument do
  @moduledoc "Builds the canonical presentation model for settlement preview, PDF, and summary."

  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation

  @type t :: map()

  @doc "Builds a settlement document model from a fully loaded delegation."
  @spec build(struct(), struct() | nil, String.t() | nil) :: t()
  def build(delegation, employment_contract, organization_logo_data_uri) do
    expenses = Enum.map(delegation.expenses, &unwrap_details/1)
    total = SettlementPresentation.sum(expenses)

    {balance_label, balance} =
      SettlementPresentation.settlement_balance(total, delegation.advance_amount)

    %{
      delegation: %{delegation | expenses: expenses},
      employee: delegation.user,
      organization: delegation.organization,
      organization_logo_data_uri: organization_logo_data_uri,
      employment_contract: employment_contract,
      expenses: expenses,
      transport_expenses: SettlementPresentation.expenses_for(expenses, :transport),
      accommodation_expenses: SettlementPresentation.expenses_for(expenses, :accommodation),
      other_expenses: SettlementPresentation.expenses_for(expenses, :other),
      transport_total: category_total(expenses, :transport),
      accommodation_total: category_total(expenses, :accommodation),
      other_total: category_total(expenses, :other),
      total: total,
      balance_label: balance_label,
      balance: balance,
      attachments: attachments(expenses)
    }
  end

  @doc "Returns the stable file name used for preview and download."
  @spec filename(struct() | t()) :: String.t()
  def filename(%{delegation: delegation}), do: filename(delegation)

  def filename(delegation) do
    "Rozliczenie_delegacji_#{delegation.settlement_sequence}-#{delegation.settlement_year}.pdf"
  end

  defp category_total(expenses, kind) do
    expenses |> SettlementPresentation.expenses_for(kind) |> SettlementPresentation.sum()
  end

  defp unwrap_details(%{details: %Ash.Union{value: details}} = expense), do: %{expense | details: details}

  defp unwrap_details(expense), do: expense

  defp attachments(expenses) do
    expenses
    |> Enum.flat_map(fn expense ->
      [expense.blob, expense.statement_blob | List.wrap(expense.related_blobs)]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end
end
