defmodule Firmowid.Invoicing.Changes.ExpectPayment do
  @moduledoc """
  Records the payment an invoice paid on issue documents as an expected transaction linked to the
  invoice, which then counts as paid. The money reaches the bank account later, often in a payment
  gateway's payout for many orders; the bank transaction that brings it fulfils the expectation.

  An invoice returned to a draft or deleted takes its expected payment back, so issuing it again
  expects the payment once and no expectation outlives its invoice.
  """
  use Ash.Resource.Change

  alias Firmowid.Finances

  @doc "Expects the payment of an issued invoice paid on issue, or withdraws it from an unnumbered or deleted one."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(%{action_type: :destroy} = changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)

    # Before the invoice goes, while its links to the expectations still exist.
    Ash.Changeset.before_action(changeset, fn changeset ->
      case withdraw(changeset.data, opts) do
        {:ok, _invoice} -> changeset
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  def change(changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)

    Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
      if invoice.invoice_number,
        do: expect(invoice, opts),
        else: withdraw(invoice, opts)
    end)
  end

  defp expect(invoice, opts) do
    with {:ok, loaded} <-
           Ash.load(
             invoice,
             [:is_paid_on_issue, :payment_date, :amount, :buyer_display_name_label],
             opts
           ),
         {:ok, _expected} <- create_expected(loaded, opts) do
      {:ok, invoice}
    end
  end

  defp create_expected(%{is_paid_on_issue: false}, _opts), do: {:ok, nil}

  defp create_expected(invoice, opts) do
    Finances.create_expected_transaction(
      %{
        date: invoice.payment_date,
        amount: invoice.amount,
        description: invoice.invoice_number,
        counterparty_name: invoice.buyer_display_name_label,
        sales_invoice_ids: [invoice.id]
      },
      opts
    )
  end

  defp withdraw(invoice, opts) do
    with {:ok, %{expected_transactions: expected}} <-
           Ash.load(invoice, :expected_transactions, opts),
         :ok <- destroy_all(expected, opts) do
      {:ok, invoice}
    end
  end

  defp destroy_all(expected, opts) do
    Enum.reduce_while(expected, :ok, fn expected_transaction, :ok ->
      case Finances.destroy_expected_transaction(expected_transaction, opts) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
