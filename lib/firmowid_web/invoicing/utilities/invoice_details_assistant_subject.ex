defmodule FirmowidWeb.Invoicing.Utilities.InvoiceDetailsAssistantSubject do
  @moduledoc """
  Assistant subject helpers scoped to invoice details flows.
  """

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice

  @doc """
  Builds a stable assistant subject reference for a linked transaction.
  """
  @spec ref(Transaction.t()) :: String.t()
  def ref(%Transaction{id: id}), do: "transaction:" <> to_string(id)

  @doc """
  Resolves the assistant subject for an invoice details action.

  When a transaction reference is provided, it returns the matching linked
  transaction. Otherwise it falls back to the invoice itself.
  """
  @spec resolve(CostInvoice.t() | SalesInvoice.t(), map()) ::
          CostInvoice.t() | SalesInvoice.t() | Transaction.t()
  def resolve(invoice, %{"assistant_subject_ref" => "transaction:" <> transaction_id}) do
    Enum.find(invoice.transactions, invoice, &(to_string(&1.id) == transaction_id))
  end

  def resolve(invoice, _params), do: invoice
end
