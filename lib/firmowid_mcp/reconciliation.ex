defmodule FirmowidMcp.Reconciliation do
  @moduledoc "Model guidance for matching bank transactions with invoices and salaries."

  @doc "Returns the payment matching instructions advertised by the MCP server."
  @spec instructions() :: String.t()
  def instructions do
    """
    Bank transactions settle invoices and monthly salaries. Use list_transactions to find them, for example
    pending ones with an amount range or a counterparty in query. Firmowid already connects confident matches
    automatically after each bank synchronization, so pending items are the ones that still need a decision.
    To find a payment for an invoice, call suggest_sales_invoice_transactions or suggest_cost_invoice_transactions;
    to find what a transaction pays, call suggest_transaction_invoices, or suggest_transaction_salaries for an
    outgoing transfer to an employee. Suggestions are ranked candidates, not decisions: compare the counterparty,
    amount, dates and transfer title, and also consider transactions or invoices the suggestions do not list.
    list_monthly_salaries shows every salary of a month, paid or not, when the right one is missing from suggestions.
    A skipped transaction must be returned to pending with restore_transaction_for_matching before connecting it.
    Present the proposed matches and connect only the ones the user approves, with connect_sales_invoice_transactions,
    connect_cost_invoice_transactions or connect_transaction_salary. Several transactions may pay one invoice and
    one transaction may pay several invoices. Disconnect tools remove only a wrong connection, never the documents
    or transactions. Connecting invoices requires an accountant or administrator; salary suggestions
    and assignments require an administrator.
    """
  end
end
