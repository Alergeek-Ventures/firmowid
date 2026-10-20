defmodule Firmowid.Ash.Invoicing.Actions.TransactionSuggestions do
  @moduledoc """
  Lists every transaction connected to one invoice and pending transactions scored against
  it by the invoice matching model. The `:load` option names the invoice fields the model reads.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Scope

  @impl true
  def run(input, opts, context) do
    scope = Scope.new!(context.actor, context.tenant)

    with {:ok, invoice} <-
           Ash.get(input.resource, input.arguments.invoice_id, load: opts[:load], scope: scope) do
      scored = InvoiceMatching.get_potential_transactions_for_invoice(invoice, scope)
      scored_ids = MapSet.new(scored, fn {transaction, _score} -> transaction.id end)
      connected_ids = MapSet.new(invoice.transactions, & &1.id)

      # The model only scores transactions within the invoice's date and amount window,
      # so connections outside it, such as installments, are listed without a score.
      unscored =
        invoice.transactions
        |> Enum.reject(&MapSet.member?(scored_ids, &1.id))
        |> Enum.map(&{&1, nil})

      {:ok,
       Enum.map(unscored ++ scored, fn {transaction, score} ->
         %{
           transaction_id: transaction.id,
           booking_date: transaction.booking_date,
           amount: transaction.amount,
           counterparty_name: counterparty_name(invoice, transaction),
           title: transaction.remittance_information_unstructured,
           connected: MapSet.member?(connected_ids, transaction.id),
           score: score
         }
       end)}
    end
  end

  defp counterparty_name(%CostInvoice{}, transaction), do: transaction.creditor_name
  defp counterparty_name(_sales_invoice, transaction), do: transaction.debtor_name
end
