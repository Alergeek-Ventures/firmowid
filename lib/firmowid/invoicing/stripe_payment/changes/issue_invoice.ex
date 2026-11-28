defmodule Firmowid.Invoicing.StripePayment.Changes.IssueInvoice do
  @moduledoc """
  Issues the invoice of a recorded Stripe payment and marks the payment invoiced, skipped when
  its buyer has no tax ID and the company does not invoice private persons, or untaxed when
  Stripe charged no tax on a line of a VAT payer's payment.

  The payment is read from Stripe with the company's key before the transaction, so a slow
  answer holds no database connection. The invoice is issued in the payment's transaction by the
  invoicing domain's own `:issue`, as `Firmowid.Billing.Payment` issues Firmowid's own: it takes
  the payment's id, is numbered and queued for KSeF, so either both the invoice and the status
  are saved or neither is. A payment of a company that disconnected Stripe in the meantime
  fails, and so does one Stripe or the invoice rejects, or whose invoice does not add up to what
  Stripe took.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.StripePayment.InvoiceInput
  alias Firmowid.LocalDate
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @doc "Reads the payment from Stripe, then issues its invoice inside the payment's transaction."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_transaction(&read_payment/1)
    |> Ash.Changeset.before_action(&issue/1)
  end

  defp read_payment(%{data: payment} = changeset) do
    with {:ok, connection} <-
           Invoicing.get_stripe_connection(
             scope: scope(payment, :stripe_invoicing),
             not_found_error?: true
           ),
         {:ok, organization} <-
           Core.get_organization(payment.organization_id,
             scope: scope(payment, :sales_invoice_processor)
           ),
         {:ok, input} <-
           InvoiceInput.build(payment.payment_intent_id, connection.api_key, %{
             invoice_consumers: connection.invoice_consumers,
             is_vat_payer: organization.is_vat_payer
           }) do
      Ash.Changeset.put_context(changeset, :invoice_input, input)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp issue(%{context: %{invoice_input: :skip}} = changeset),
    do: Ash.Changeset.force_change_attribute(changeset, :status, :skipped)

  defp issue(%{context: %{invoice_input: :untaxed}} = changeset),
    do: Ash.Changeset.force_change_attribute(changeset, :status, :untaxed)

  defp issue(%{data: payment, context: %{invoice_input: input}} = changeset) do
    scope = scope(payment, :sales_invoice_processor)

    with {:ok, invoice_number} <-
           SalesInvoice.get_next_number(LocalDate.today(), nil, nil, scope: scope),
         {:ok, invoice} <-
           Invoicing.issue_sales_invoice(
             %{
               confirmation_id: payment.id,
               input: Map.put(input, :invoice_number, invoice_number)
             },
             scope: scope
           ),
         {:ok, %{rounded_gross_value: gross}} <-
           Ash.load(invoice, :rounded_gross_value, scope: scope),
         :ok <- adds_up(gross, payment.amount) do
      Ash.Changeset.force_change_attribute(changeset, :status, :invoiced)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # The invoice computes its VAT on each line's net and rounds only its total, while Stripe may
  # round the tax of each line, so the two can differ by a grosz. An invoice showing another
  # amount than the buyer paid is not issued: the error rolls it back.
  defp adds_up(gross, amount) do
    if Decimal.eq?(gross, amount),
      do: :ok,
      else: {:error, "the invoice adds up to #{gross}, Stripe took #{amount}"}
  end

  defp scope(payment, role) do
    Scope.new!(%SystemActor{org_id: payment.organization_id, role: role}, payment.organization_id)
  end
end
