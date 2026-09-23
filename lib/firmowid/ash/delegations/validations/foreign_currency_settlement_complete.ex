defmodule Firmowid.Ash.Delegations.Validations.ForeignCurrencySettlementComplete do
  @moduledoc "Requires complete settlement evidence for expenses recorded in a foreign currency."

  use Ash.Resource.Validation

  @company_currency :PLN

  @impl true
  def validate(changeset, _opts, _context) do
    amount = attribute(changeset, :expense_amount)

    if Money.to_currency_code(amount) == @company_currency do
      :ok
    else
      validate_settlement(changeset)
    end
  end

  defp validate_settlement(changeset) do
    case attribute(changeset, :settlement_method) do
      :statement -> validate_statement(changeset)
      :nbp -> validate_nbp(changeset)
      _ -> {:error, field: :settlement_method, message: "Wybierz sposób przeliczenia waluty."}
    end
  end

  defp validate_statement(changeset) do
    if positive_money?(attribute(changeset, :settlement_amount)) and
         attribute(changeset, :statement_blob_id) do
      :ok
    else
      {:error, field: :settlement_amount, message: "Podaj kwotę z wyciągu i wgraj dokument."}
    end
  end

  defp validate_nbp(changeset) do
    if positive_money?(attribute(changeset, :settlement_amount)) and
         positive_decimal?(attribute(changeset, :nbp_rate)) and
         attribute(changeset, :nbp_rate_date) do
      :ok
    else
      {:error, field: :settlement_amount, message: "Nie udało się ustalić kursu NBP."}
    end
  end

  defp positive_money?(%Money{} = amount), do: not Money.zero?(amount)
  defp positive_money?(_), do: false

  defp positive_decimal?(%Decimal{} = value), do: Decimal.compare(value, 0) == :gt
  defp positive_decimal?(_), do: false

  defp attribute(changeset, name), do: Ash.Changeset.get_attribute(changeset, name) || Map.get(changeset.data, name)
end
