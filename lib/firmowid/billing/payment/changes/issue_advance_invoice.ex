defmodule Firmowid.Billing.Payment.Changes.IssueAdvanceInvoice do
  @moduledoc """
  Issues the advance invoice (KSeF ZAL) for a paid payment and marks the payment invoiced.

  The paid invoice is read from Stripe before the transaction, so a slow answer holds no
  database connection; `Firmowid.Billing.Payment.AdvanceInvoice` says what it puts on the
  invoice.

  The issuer is the payment's own organization: the invoice is issued in its tenant by the
  invoicing domain's own `:issue`, so it is numbered, queued for KSeF and, once KSeF confirms
  it, delivered to the buyer like any other invoice.

  The invoice takes the payment's id and is issued in the payment's transaction, so either
  both the invoice and `invoiced_at` are saved or neither is. A buyer without a tax id, a line
  without a description or an issuer without a KSeF connection fails the issue, and the hourly
  trigger tries again.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing.Payment.AdvanceInvoice
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.LocalDate
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @doc "Reads the paid Stripe invoice, then issues the advance invoice inside the payment's transaction."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_transaction(&read_stripe_invoice/1)
    |> Ash.Changeset.before_action(&issue/1)
  end

  defp read_stripe_invoice(changeset) do
    with {:ok, invoice} <-
           StripeTerms.request(:get, "/v1/invoices/#{changeset.data.stripe_invoice_id}"),
         {:ok, input} <- AdvanceInvoice.input(invoice) do
      Ash.Changeset.put_context(changeset, :advance_invoice, input)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp issue(%{data: payment, context: %{advance_invoice: input}} = changeset) do
    issuer_scope = issuer_scope(payment)

    with {:ok, invoice_number} <-
           SalesInvoice.get_next_number(LocalDate.today(), nil, nil, scope: issuer_scope),
         {:ok, _invoice} <-
           Invoicing.issue_sales_invoice(
             %{
               confirmation_id: payment.id,
               input: Map.put(input, :invoice_number, invoice_number)
             },
             scope: issuer_scope
           ) do
      Ash.Changeset.force_change_attribute(changeset, :invoiced_at, DateTime.utc_now())
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp issuer_scope(payment) do
    Scope.new!(
      %SystemActor{org_id: payment.organization_id, role: :sales_invoice_processor},
      payment.organization_id
    )
  end
end
