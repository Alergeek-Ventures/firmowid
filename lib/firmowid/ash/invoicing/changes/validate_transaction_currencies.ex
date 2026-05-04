defmodule Firmowid.Ash.Invoicing.Changes.ValidateTransactionCurrencies do
  @moduledoc """
  Ensures linked transactions use the same currency as the invoice.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.Finances

  @impl true
  def change(changeset, _opts, context) do
    case Ash.Changeset.get_argument(changeset, :transaction_ids) do
      transaction_ids when is_list(transaction_ids) and transaction_ids != [] ->
        validate_transaction_currencies(changeset, transaction_ids, context)

      _ ->
        changeset
    end
  end

  defp validate_transaction_currencies(changeset, transaction_ids, context) do
    ash_opts = Ash.Context.to_opts(context)

    with {:ok, invoice_currency} <- invoice_currency(changeset.data, ash_opts),
         {:ok, transactions} <- fetch_transactions(transaction_ids, ash_opts) do
      case mismatched_currencies(transactions, invoice_currency) do
        [] ->
          changeset

        mismatched_currencies ->
          Ash.Changeset.add_error(changeset,
            field: :transaction_ids,
            message: mismatch_message(invoice_currency, mismatched_currencies)
          )
      end
    else
      {:error, :invoice_currency_unavailable} ->
        add_lookup_error(changeset, "Nie udało się ustalić waluty faktury.")

      {:error, _reason} ->
        add_lookup_error(changeset, "Nie udało się pobrać transakcji do walidacji waluty.")
    end
  end

  defp invoice_currency(invoice, ash_opts) do
    with {:ok, loaded_invoice} <- Ash.load(invoice, [:effective_currency], ash_opts),
         currency when is_binary(currency) and currency != "" <-
           effective_currency(loaded_invoice) do
      {:ok, currency}
    else
      _ -> {:error, :invoice_currency_unavailable}
    end
  end

  defp fetch_transactions(transaction_ids, ash_opts) do
    transaction_ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn transaction_id, {:ok, transactions} ->
      case Finances.get_transaction(transaction_id, ash_opts) do
        {:ok, transaction} -> {:cont, {:ok, [transaction | transactions]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, transactions} -> {:ok, Enum.reverse(transactions)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp mismatched_currencies(transactions, invoice_currency) do
    transactions
    |> Enum.map(& &1.transaction_currency)
    |> Enum.reject(&(&1 == invoice_currency))
    |> Enum.uniq()
  end

  defp mismatch_message(invoice_currency, mismatched_currencies) do
    mismatched_currencies = Enum.join(mismatched_currencies, ", ")

    "Nie można połączyć faktury w walucie #{invoice_currency} z transakcjami w walutach: #{mismatched_currencies}."
  end

  defp add_lookup_error(changeset, message) do
    Ash.Changeset.add_error(
      changeset,
      InvalidAttribute.exception(field: :transaction_ids, message: message)
    )
  end

  defp effective_currency(invoice), do: Map.get(invoice, :effective_currency) || Map.get(invoice, :currency)
end
