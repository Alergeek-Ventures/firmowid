defmodule Firmowid.Invoicing.StripeRefund.Changes.CorrectInvoice do
  @moduledoc """
  Corrects the invoice of a refunded Stripe payment and marks the refund corrected, or marks why
  the integration leaves the correction to the company.

  What the correction says is read from Stripe with the company's key before the transaction:

  - a refund that, with the refunds before it, returns the whole payment corrects the invoice to
    zero, like cancelling it;
  - a partial refund of a paid Stripe invoice with a credit note lowers each line by the net the
    note credits it (the shipping too); the lines are the Stripe invoice's, in its order, as
    `InvoiceInput` issued them;
  - any other partial refund says only how much went back, not of which lines, and Firmowid
    does not guess: the refund is `:manual`.

  A refund of a payment skipped for a buyer without a tax ID needs nothing (`:skipped`); one of a
  payment that got no invoice from Firmowid is `:manual`. The correction is issued in the
  refund's transaction by the invoicing domain's own `:correct` in the FK series, takes the
  refund's id and is queued for KSeF. A correction that would not add up to what the buyer kept
  is not issued: the error rolls it back.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.Services.CorrectionReason
  alias Firmowid.LocalDate
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  @snapshot_load [
    :sales_invoice_items,
    :invoice_type,
    :sale_date,
    :due_date,
    :payment_method,
    :is_cash_account,
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_pesel,
    :buyer_display_name,
    :buyer_address,
    :buyer_country,
    :buyer_is_different_mail_address,
    :buyer_mail_address,
    :buyer_mail_country,
    :buyer_email,
    :buyer_phone,
    :buyer_description
  ]

  @doc "Reads the refund from Stripe, then corrects the invoice inside the refund's transaction."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_transaction(&read_refund/1)
    |> Ash.Changeset.before_action(&correct/1)
  end

  defp read_refund(%{data: refund} = changeset) do
    scope = scope(refund, :stripe_invoicing)

    with {:ok, %{stripe_payment: payment}} <- Ash.load(refund, :stripe_payment, scope: scope),
         {:ok, plan} <- plan(refund, payment, scope) do
      changeset
      |> Ash.Changeset.put_context(:correction, plan)
      |> Ash.Changeset.put_context(:payment, payment)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp plan(_refund, %{status: :skipped}, _scope), do: {:ok, :skipped}

  defp plan(_refund, %{status: status}, _scope) when status in [:untaxed, :failed], do: {:ok, {:manual, :no_invoice}}

  defp plan(refund, %{status: :invoiced} = payment, scope) do
    with {:ok, connection} <-
           Invoicing.get_stripe_connection(scope: scope, not_found_error?: true) do
      request = &StripeTerms.request(:get, &1, &2, api_key: connection.api_key)

      with {:ok, refunded} <- refunded(refund, request) do
        if Decimal.eq?(refunded, payment.amount),
          do: {:ok, {:correct, :zero, Decimal.new(0)}},
          else: credit_note(refund, Decimal.sub(payment.amount, refunded), request)
      end
    end
  end

  # What the refunds of the payment up to this one returned. Stripe lists them newest first, so
  # this one and the ones after it are its history, also within one second.
  defp refunded(refund, request) do
    with {:ok, refunds} <-
           StripeTerms.list(request, "/v1/refunds", %{payment_intent: refund.payment_intent_id}) do
      grosze =
        refunds
        |> Enum.drop_while(&(&1["id"] != refund.refund_id))
        |> Enum.filter(&(&1["status"] == "succeeded"))
        |> Enum.sum_by(& &1["amount"])

      {:ok, StripeTerms.pln(grosze)}
    end
  end

  defp credit_note(refund, kept, request) do
    with {:ok, %{"data" => invoice_payments}} <-
           request.("/v1/invoice_payments", %{
             payment: %{type: "payment_intent", payment_intent: refund.payment_intent_id}
           }) do
      case invoice_payments do
        [%{"invoice" => invoice_id} | _rest] ->
          invoice_credit_note(refund, invoice_id, kept, request)

        [] ->
          {:ok, {:manual, :no_credit_note}}
      end
    end
  end

  defp invoice_credit_note(refund, invoice_id, kept, request) do
    with {:ok, notes} <- StripeTerms.list(request, "/v1/credit_notes", %{invoice: invoice_id}) do
      case Enum.find(notes, &(&1["status"] == "issued" and refunds?(&1, refund.refund_id))) do
        nil -> {:ok, {:manual, :no_credit_note}}
        note -> credited(note, invoice_id, kept, request)
      end
    end
  end

  defp refunds?(note, refund_id), do: Enum.any?(note["refunds"] || [], &(&1["refund"] == refund_id))

  # The net the note credits each line of the invoice, by the line's position, with the units it
  # credits when the note credits units rather than an amount.
  defp credited(note, invoice_id, kept, request) do
    with {:ok, lines} <- StripeTerms.list(request, "/v1/credit_notes/#{note["id"]}/lines"),
         {:ok, invoice_lines} <- StripeTerms.list(request, "/v1/invoices/#{invoice_id}/lines") do
      positions = invoice_lines |> Enum.map(& &1["id"]) |> Enum.with_index() |> Map.new()

      lines
      |> Enum.reduce_while(%{}, fn line, credited ->
        case positions[line["invoice_line_item"]] do
          nil ->
            {:halt, :unmatched}

          position ->
            {:cont, Map.update(credited, position, credit(line), &add_credit(&1, credit(line)))}
        end
      end)
      |> case do
        :unmatched -> {:ok, {:manual, :credit_note_lines}}
        credited -> {:ok, {:correct, add_shipping(credited, note, length(invoice_lines)), kept}}
      end
    end
  end

  defp credit(line), do: {net(line), line["quantity"]}

  defp add_credit({net, quantity}, {more_net, more_quantity}) when is_integer(quantity) and is_integer(more_quantity),
    do: {net + more_net, quantity + more_quantity}

  defp add_credit({net, _quantity}, {more_net, _more_quantity}), do: {net + more_net, nil}

  # As `InvoiceInput` reads an invoice line: the net Stripe charged its tax on, else the amount
  # less its discounts.
  defp net(%{"taxes" => [%{"amount" => tax, "taxable_amount" => taxed} | _rest]}) when tax != 0, do: taxed

  defp net(line), do: line["amount"] - (line["discount_amount"] || 0)

  # The shipping line comes after the invoice's lines.
  defp add_shipping(credited, %{"shipping_cost" => %{"amount_total" => gross} = shipping}, position) when gross > 0,
    do: Map.put(credited, position, {gross - (shipping["amount_tax"] || 0), nil})

  defp add_shipping(credited, _note, _position), do: credited

  defp correct(%{context: %{correction: :skipped}} = changeset),
    do: Ash.Changeset.force_change_attribute(changeset, :status, :skipped)

  defp correct(%{context: %{correction: {:manual, reason}}} = changeset) do
    changeset
    |> Ash.Changeset.force_change_attribute(:status, :manual)
    |> Ash.Changeset.force_change_attribute(:manual_reason, reason)
  end

  defp correct(%{data: refund, context: %{correction: {:correct, credited, kept}, payment: payment}} = changeset) do
    scope = scope(refund, :sales_invoice_processor)
    issue_date = LocalDate.today()

    with {:ok, %{sales_invoice: invoice}} <-
           Ash.load(payment, [sales_invoice: [:effective_snapshot]], scope: scope),
         {:ok, latest} <- Ash.load(invoice.effective_snapshot, @snapshot_load, scope: scope),
         {:ok, items} <- items(latest.sales_invoice_items, credited),
         {:ok, invoice_number} <-
           issue_date
           |> SalesInvoice.input_to_get_next_number("FK", nil, scope: scope)
           |> Ash.run_action(),
         {:ok, correction} <-
           Invoicing.correct_sales_invoice(
             %{
               original_invoice_id: invoice.id,
               confirmation_id: refund.id,
               invoice_number: invoice_number,
               issue_date: issue_date,
               sale_date: latest.sale_date,
               # A correction does not state a payment date, so the payment's day is its term.
               due_date: latest.due_date || latest.paid_on,
               correction_reason: CorrectionReason.generate(%{latest | sales_invoice_items: items}, latest),
               sales_invoice_items: items
             },
             scope: scope
           ),
         {:ok, %{rounded_gross_value: gross}} <-
           Ash.load(correction, :rounded_gross_value, scope: scope),
         :ok <- adds_up(gross, kept) do
      Ash.Changeset.force_change_attribute(changeset, :status, :corrected)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # Every line of the latest state again, as a correction states them: at zero, or lowered by the
  # net the credit note credits it.
  defp items(items, credited) do
    items
    |> Enum.sort_by(& &1.index)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, position}, {:ok, acc} ->
      case item(item, credited, position) do
        {:ok, item} -> {:cont, {:ok, acc ++ [item]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp item(item, :zero, _position), do: {:ok, item |> fields() |> Map.put(:quantity, Decimal.new(0))}

  defp item(item, credited, position) do
    case Map.fetch(credited, position) do
      :error ->
        {:ok, fields(item)}

      {:ok, {grosze, units}} ->
        lower(item, StripeTerms.pln(grosze), units)
    end
  end

  # Units the note credits at the line's price lower the quantity; any other credit lowers the
  # price, and one that leaves nothing the quantity to zero.
  defp lower(item, credited, units) do
    net = item.unit_price |> Decimal.mult(item.quantity) |> Decimal.sub(credited)

    cond do
      Decimal.eq?(credited, 0) ->
        {:ok, fields(item)}

      Decimal.negative?(net) ->
        {:error, "the credit note credits #{item.name} more than it is worth"}

      Decimal.eq?(net, 0) ->
        {:ok, item |> fields() |> Map.put(:quantity, Decimal.new(0))}

      is_integer(units) and Decimal.eq?(Decimal.mult(item.unit_price, units), credited) ->
        {:ok, item |> fields() |> Map.put(:quantity, Decimal.sub(item.quantity, units))}

      true ->
        {:ok, item |> fields() |> Map.put(:unit_price, Decimal.div(net, item.quantity))}
    end
  end

  defp fields(item) do
    item
    |> Map.take([:index, :name, :quantity, :unit, :unit_price, :vat_rate, :gtu])
    |> Map.put(:discount, nil)
  end

  # Like the invoice of the payment: a correction showing another amount than the buyer kept is
  # not issued.
  defp adds_up(gross, kept) do
    if Decimal.eq?(gross, kept),
      do: :ok,
      else: {:error, "the correction adds up to #{gross}, the buyer kept #{kept}"}
  end

  defp scope(refund, role) do
    Scope.new!(%SystemActor{org_id: refund.organization_id, role: role}, refund.organization_id)
  end
end
