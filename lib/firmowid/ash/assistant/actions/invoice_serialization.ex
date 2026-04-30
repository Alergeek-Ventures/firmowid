defmodule Firmowid.Ash.Assistant.Actions.InvoiceSerialization do
  @moduledoc """
  Shared serializer helpers for assistant invoice tool payloads.
  """

  @doc """
  Serializes a cost invoice into the assistant-facing payload.
  """
  @spec serialize_cost_invoice(struct()) :: map()
  def serialize_cost_invoice(invoice) do
    %{
      id: invoice.id,
      type: "cost_invoice",
      seller: invoice.seller,
      seller_display_name: invoice.seller_display_name,
      invoice_identifier: invoice.invoice_identifier,
      description: invoice.description,
      issue_date: invoice.issue_date,
      sale_date: invoice.sale_date,
      due_date: invoice.due_date,
      currency: invoice.currency,
      total_amount: invoice.total_amount,
      skip_invoicing: invoice.skip_invoicing
    }
  end

  @doc """
  Serializes a sales invoice into the assistant-facing payload.
  """
  @spec serialize_sales_invoice(struct()) :: map()
  def serialize_sales_invoice(invoice) do
    %{
      id: invoice.id,
      type: "sales_invoice",
      invoice_number: invoice.invoice_number,
      buyer_full_name: invoice.buyer_full_name,
      buyer_description: invoice.buyer_description,
      buyer_email: invoice.buyer_email,
      issue_date: invoice.issue_date,
      sale_date: invoice.sale_date,
      due_date: invoice.due_date,
      currency: invoice.currency,
      gross_value: invoice.gross_value,
      skip_invoicing: invoice.skip_invoicing
    }
  end
end
