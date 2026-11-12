defmodule Firmowid.Invoicing.Actions.CancelInvoice do
  @moduledoc """
  Cancels a KSeF-submitted VAT invoice by issuing a correction in the FK series
  that keeps the latest effective items with zero quantities.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.Services.CorrectionReason
  alias Firmowid.LocalDate

  @correction_snapshot_load [
    :sales_invoice_items,
    :sale_date,
    :due_date,
    :invoice_type,
    :seller_nip,
    :seller_display_name,
    :seller_address,
    :seller_name,
    :seller_surname,
    :seller_account_number,
    :counterparty_id,
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_display_name,
    :buyer_address,
    :buyer_country,
    :buyer_is_different_mail_address,
    :buyer_mail_address,
    :buyer_mail_country,
    :buyer_email,
    :buyer_phone,
    :buyer_description,
    :buyer_pesel,
    :payment_method,
    :currency,
    :is_reverse_charge,
    :is_cash_account
  ]

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)

    invoice =
      SalesInvoice
      |> Ash.get!(input.arguments.invoice_id, opts)
      |> Ash.load!([:effective_snapshot], opts)

    if invoice.ksef_invoice_kind == :vat and invoice.ksef_number != nil do
      latest = Ash.load!(invoice.effective_snapshot, @correction_snapshot_load, opts)

      issue_date = LocalDate.today()

      # Get next FK-series number
      {:ok, invoice_number} =
        issue_date
        |> SalesInvoice.input_to_get_next_number("FK", nil, opts)
        |> Ash.run_action(opts)

      zeroed_items =
        Enum.map(latest.sales_invoice_items, fn item ->
          item
          |> Map.take([:index, :name, :unit, :unit_price, :vat_rate, :gtu])
          |> Map.put(:quantity, Decimal.new(0))
        end)

      correction_reason =
        Ash.ActionInput.get_argument(input, :correction_reason) ||
          CorrectionReason.cancellation(latest.invoice_type)

      Ash.create(
        SalesInvoice,
        %{
          original_invoice_id: invoice.id,
          invoice_number: invoice_number,
          issue_date: issue_date,
          sale_date: latest.sale_date,
          due_date: latest.due_date,
          correction_reason: correction_reason,
          sales_invoice_items: zeroed_items,
          confirm_corrected_buyer_vat_id: input.arguments.confirm_corrected_buyer_vat_id
        },
        Keyword.put(opts, :action, :correct)
      )
    else
      {:error, "can only cancel KSeF-submitted VAT invoices"}
    end
  end
end
