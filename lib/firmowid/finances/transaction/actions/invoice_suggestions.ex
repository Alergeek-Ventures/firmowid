defmodule Firmowid.Finances.Transaction.Actions.InvoiceSuggestions do
  @moduledoc "Lists unresolved invoices scored against a pending transaction by the invoice matching model."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Finances
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.InvoiceMatching
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope

  @impl true
  def run(input, _opts, context) do
    scope = Scope.new!(context.actor, context.tenant)

    with {:ok, transaction} <-
           Finances.get_transaction(input.arguments.transaction_id, scope: scope) do
      {:ok,
       transaction
       |> InvoiceMatching.get_potential_invoices_for_transaction(scope)
       |> Enum.map(fn {invoice, score} -> suggestion(invoice, score) end)}
    end
  end

  defp suggestion(%CostInvoice{} = invoice, score) do
    %{
      invoice_type: :cost,
      invoice_id: invoice.id,
      invoice_number: invoice.invoice_identifier,
      counterparty_name: invoice.effective_seller_display_name,
      issue_date: invoice.issue_date,
      due_date: invoice.due_date,
      effective_amount: invoice.effective_amount,
      score: score
    }
  end

  defp suggestion(%SalesInvoice{} = invoice, score) do
    %{
      invoice_type: :sales,
      invoice_id: invoice.id,
      invoice_number: invoice.invoice_number,
      counterparty_name: invoice.buyer_display_name_label,
      issue_date: invoice.issue_date,
      due_date: invoice.due_date,
      effective_amount: invoice.effective_amount,
      score: score
    }
  end
end
