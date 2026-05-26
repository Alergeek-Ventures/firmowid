defmodule Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailContentBuilder do
  @moduledoc """
  Builds subject, text body, and HTML body for sales invoice emails.
  """

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceChain

  @doc """
  Builds localized email content for a sales invoice delivery type.
  """
  @spec build(SalesInvoice.t(), :basic | :reminder | :invoice_correction, String.t(), keyword()) ::
          {String.t(), String.t(), String.t()}
  def build(invoice, :basic, share_url, _ash_opts) do
    {share_en, share_pl} = share_line(share_url)
    {sender_en, sender_pl} = sender_organization_line(invoice)
    invoice_number = invoice.invoice_number
    due_date = format_date(invoice.due_date)

    subject = "Invoice #{invoice_number} / Faktura #{invoice_number}"

    text =
      """
      Hello,

      #{sender_en}
      Attached is your invoice #{invoice_number}.
      Due date: #{due_date}.
      #{share_en}

      ---

      Dzień dobry,

      #{sender_pl}
      w załączniku przesyłamy fakturę #{invoice_number}.
      Termin płatności: #{due_date}.
      #{share_pl}
      """

    html =
      """
      <p>Hello,</p>
      <p>#{sender_en}</p>
      <p>Attached is your invoice <strong>#{invoice_number}</strong>.</p>
      <p>Due date: <strong>#{due_date}</strong>.</p>
      <p>#{share_en}</p>
      <hr>
      <p>Dzień dobry,</p>
      <p>#{sender_pl}</p>
      <p>w załączniku przesyłamy fakturę <strong>#{invoice_number}</strong>.</p>
      <p>Termin płatności: <strong>#{due_date}</strong>.</p>
      <p>#{share_pl}</p>
      """

    {subject, text, html}
  end

  def build(invoice, :reminder, share_url, _ash_opts) do
    {share_en, share_pl} = share_line(share_url)
    {sender_en, sender_pl} = sender_organization_line(invoice)
    invoice_number = invoice.invoice_number
    due_date = format_date(invoice.due_date)

    subject = "Payment Reminder: #{invoice_number} / Przypomnienie o płatności: #{invoice_number}"

    text =
      """
      Hello,

      #{sender_en}
      this is a payment reminder for invoice #{invoice_number}.
      Due date: #{due_date}.
      #{share_en}

      ---

      Dzień dobry,

      #{sender_pl}
      przypominamy o płatności dla faktury #{invoice_number}.
      Termin płatności: #{due_date}.
      #{share_pl}
      """

    html =
      """
      <p>Hello,</p>
      <p>#{sender_en}</p>
      <p>this is a payment reminder for invoice <strong>#{invoice_number}</strong>.</p>
      <p>Due date: <strong>#{due_date}</strong>.</p>
      <p>#{share_en}</p>
      <hr>
      <p>Dzień dobry,</p>
      <p>#{sender_pl}</p>
      <p>przypominamy o płatności dla faktury <strong>#{invoice_number}</strong>.</p>
      <p>Termin płatności: <strong>#{due_date}</strong>.</p>
      <p>#{share_pl}</p>
      """

    {subject, text, html}
  end

  def build(invoice, :invoice_correction, share_url, ash_opts) do
    {share_en, share_pl} = share_line(share_url)
    {sender_en, sender_pl} = sender_organization_line(invoice)

    {prev_number_en, prev_number_pl} =
      previous_invoice_number(SalesInvoiceChain.previous_invoice(invoice, ash_opts))

    invoice_number = invoice.invoice_number
    due_date = format_date(invoice.due_date)

    subject = "Invoice Correction: #{prev_number_en} / Korekta faktury #{prev_number_pl}"

    text =
      """
      Hello,

      #{sender_en}
      we have corrected invoice #{prev_number_en}. Attached is correcting invoice #{invoice_number}.
      Due date: #{due_date}.
      #{share_en}

      ---

      Dzień dobry,

      #{sender_pl}
      skorygowaliśmy fakturę #{prev_number_pl}. W załączniku przesyłamy fakturę korygującą #{invoice_number}.
      Termin płatności: #{due_date}.
      #{share_pl}
      """

    html =
      """
      <p>Hello,</p>
      <p>#{sender_en}</p>
      <p>we have corrected invoice <strong>#{prev_number_en}</strong>. Attached is correcting invoice <strong>#{invoice_number}</strong>.</p>
      <p>Due date: <strong>#{due_date}</strong>.</p>
      <p>#{share_en}</p>
      <hr>
      <p>Dzień dobry,</p>
      <p>#{sender_pl}</p>
      <p>skorygowaliśmy fakturę <strong>#{prev_number_pl}</strong>. W załączniku przesyłamy fakturę korygującą <strong>#{invoice_number}</strong>.</p>
      <p>Termin płatności: <strong>#{due_date}</strong>.</p>
      <p>#{share_pl}</p>
      """

    {subject, text, html}
  end

  defp previous_invoice_number(%{invoice_number: invoice_number}) when is_binary(invoice_number),
    do: {invoice_number, invoice_number}

  defp previous_invoice_number(_previous_invoice), do: {"the previous invoice", "poprzednią fakturę"}

  defp share_line(url) when is_binary(url) and url != "" do
    {"Online preview: #{url}", "Podgląd online: #{url}"}
  end

  defp share_line(_url), do: {"", ""}

  defp sender_organization_line(invoice) do
    name = invoice.seller_display_name
    address = invoice.seller_address

    en_name = name || "the seller"
    pl_name = name || "wystawcy faktury"

    en_base = "Message sent on behalf of: #{en_name}"
    pl_base = "Wiadomość wysyłamy w imieniu: #{pl_name}"

    if is_binary(address) and String.trim(address) != "" do
      {"#{en_base}, address: #{address}.", "#{pl_base}, adres: #{address}."}
    else
      {"#{en_base}.", "#{pl_base}."}
    end
  end

  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(_), do: "-"
end
