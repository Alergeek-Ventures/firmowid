defmodule Firmowid.Ash.Invoicing.Actions.SendSalesInvoiceEmail do
  @moduledoc """
  Sends a sales invoice email via Resend and persists delivery outcome.
  """
  use Ash.Resource.Actions.Implementation

  import Swoosh.Email

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice.EmailRecipientEligibility
  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.Invoicing.Services.Pdf
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailContentBuilder
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceSharing
  alias Firmowid.Ash.Scope
  alias Firmowid.Mailer

  require Logger

  @generic_send_failure_message "Nie udało się wysłać wiadomości email"

  @impl true
  def run(input, _opts, context) do
    ash_opts = Ash.Context.to_opts(context)
    scope = %Scope{actor: context.actor, tenant: context.tenant}
    sales_invoice_id = input.arguments.sales_invoice_id
    delivery_type = input.arguments.delivery_type

    case SalesInvoice.by_id(sales_invoice_id, Keyword.put(ash_opts, :load, [:counterparty])) do
      {:ok, nil} ->
        {:error, :sales_invoice_not_found}

      {:ok, invoice} ->
        send_invoice_email(invoice, delivery_type, scope, ash_opts)

      {:error, reason} ->
        {:error, reason}
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
        _ =
          handle_delivery_failure(
            invoice,
            delivery_type,
            recipient_email,
            reason,
            reason,
            ash_opts
          )

        {:error, reason}
    end
  end

  defp send_invoice_email_to_valid_recipient(invoice, delivery_type, recipient_email, scope, ash_opts) do
    with {:ok, share_url} <- SalesInvoiceSharing.get_share_url_for_sales_invoice(invoice, scope),
         {:ok, pdf_binary} <- Pdf.generate(invoice, scope: scope, include_internal_note: false),
         {:ok, resend_response} <-
           deliver_email(
             invoice,
             delivery_type,
             recipient_email,
             share_url,
             pdf_binary,
             ash_opts
           ),
         {:ok, delivery} <-
           record_sent_delivery(
             invoice,
             delivery_type,
             recipient_email,
             resend_response,
             ash_opts
           ) do
      {:ok, delivery}
    else
      {:error, reason} ->
        public_message = @generic_send_failure_message

        _ =
          handle_delivery_failure(
            invoice,
            delivery_type,
            recipient_email,
            public_message,
            reason,
            ash_opts
          )

        {:error, reason}
    end
  end

  defp record_sent_delivery(invoice, delivery_type, recipient_email, resend_response, ash_opts) do
    SalesInvoiceEmailDelivery
    |> Ash.Changeset.for_create(
      :record_delivery,
      %{
        sales_invoice_id: invoice.id,
        delivery_type: delivery_type,
        status: :sent,
        recipient_email: recipient_email,
        resend_email_id: resend_response.id,
        sent_at: DateTime.utc_now()
      },
      ash_opts
    )
    |> Ash.create(ash_opts)
  end

  defp handle_delivery_failure(invoice, delivery_type, recipient_email, public_message, reason, ash_opts) do
    Logger.error(
      "Sales invoice email runtime failure invoice_id=#{invoice.id} " <>
        "delivery_type=#{delivery_type} reason=#{inspect(reason)}"
    )

    SalesInvoiceEmailDelivery
    |> Ash.Changeset.for_create(
      :record_delivery,
      %{
        sales_invoice_id: invoice.id,
        delivery_type: delivery_type,
        status: :failed,
        recipient_email: recipient_email,
        resend_email_id: nil,
        error_message: public_message,
        failed_at: DateTime.utc_now()
      },
      ash_opts
    )
    |> Ash.create(ash_opts)
  end

  defp deliver_email(invoice, delivery_type, recipient_email, share_url, pdf_binary, ash_opts) do
    {subject, text_body, html_body} =
      SalesInvoiceEmailContentBuilder.build(invoice, delivery_type, share_url, ash_opts)

    pdf_attachment =
      Swoosh.Attachment.new({:data, pdf_binary},
        filename: "#{invoice.invoice_number || "faktura"}.pdf",
        content_type: "application/pdf"
      )

    email =
      new()
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> to(recipient_email)
      |> subject(subject)
      |> text_body(text_body)
      |> html_body(html_body)
      |> attachment(pdf_attachment)

    Mailer.deliver(email)
  end
end
