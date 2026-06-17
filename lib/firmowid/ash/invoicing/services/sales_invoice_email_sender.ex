defmodule Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailSender do
  @moduledoc """
  Sends sales invoice emails and returns delivery outcome attributes.
  """

  import Swoosh.Email

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice.EmailRecipientEligibility
  alias Firmowid.Ash.Invoicing.Services.Pdf
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailContentBuilder
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceSharing
  alias Firmowid.Ash.Scope
  alias Firmowid.Mailer

  @generic_send_failure_message "Nie udało się wysłać wiadomości email"

  @doc """
  Sends a sales invoice email and returns attrs for the final delivery record.
  """
  @spec deliver(Ash.UUID.t(), atom(), Scope.t()) ::
          {:ok, map()} | {:error, map(), term()} | {:cancel, term()}
  def deliver(sales_invoice_id, delivery_type, %Scope{} = scope) do
    ash_opts = [scope: scope]

    case SalesInvoice.by_id(sales_invoice_id, Keyword.put(ash_opts, :load, [:counterparty])) do
      {:ok, nil} ->
        {:cancel, :sales_invoice_not_found}

      {:ok, invoice} ->
        send_invoice_email(invoice, delivery_type, scope, ash_opts)

      {:error, reason} ->
        {:error,
         %{
           sales_invoice_id: sales_invoice_id,
           delivery_type: delivery_type,
           recipient_email: nil,
           error_message: @generic_send_failure_message
         }, reason}
    end
  end

  defp send_invoice_email(invoice, delivery_type, scope, ash_opts) do
    case EmailRecipientEligibility.fetch_valid_counterparty_email(invoice.counterparty_id, scope) do
      {:ok, recipient_email} ->
        send_invoice_email_to_valid_recipient(
          invoice,
          delivery_type,
          recipient_email,
          scope,
          ash_opts
        )

      {:error, reason, recipient_email} ->
        {:error,
         %{
           sales_invoice_id: invoice.id,
           delivery_type: delivery_type,
           recipient_email: recipient_email,
           error_message: reason
         }, reason}
    end
  end

  defp send_invoice_email_to_valid_recipient(invoice, delivery_type, recipient_email, scope, ash_opts) do
    with {:ok, share_url} <- SalesInvoiceSharing.get_share_url_for_sales_invoice(invoice, scope),
         {:ok, pdf_binary} <- Pdf.generate(invoice, scope: scope, include_internal_note: false),
         {:ok, resend_response} <-
           deliver_email(invoice, delivery_type, recipient_email, share_url, pdf_binary, ash_opts) do
      {:ok,
       %{
         sales_invoice_id: invoice.id,
         delivery_type: delivery_type,
         recipient_email: recipient_email,
         resend_email_id: resend_response.id
       }}
    else
      {:error, reason} ->
        {:error,
         %{
           sales_invoice_id: invoice.id,
           delivery_type: delivery_type,
           recipient_email: recipient_email,
           error_message: @generic_send_failure_message
         }, reason}
    end
  end

  defp deliver_email(invoice, delivery_type, recipient_email, share_url, pdf_binary, ash_opts) do
    {subject, text_body, html_body} =
      SalesInvoiceEmailContentBuilder.build(invoice, delivery_type, share_url, ash_opts)

    pdf_attachment =
      Swoosh.Attachment.new({:data, pdf_binary},
        filename: "#{invoice.invoice_number || "faktura"}.pdf",
        content_type: "application/pdf"
      )

    new()
    |> from({"Firmowid", "piotr@firmowid.pl"})
    |> to(recipient_email)
    |> subject(subject)
    |> text_body(text_body)
    |> html_body(html_body)
    |> attachment(pdf_attachment)
    |> Mailer.deliver()
  end
end
