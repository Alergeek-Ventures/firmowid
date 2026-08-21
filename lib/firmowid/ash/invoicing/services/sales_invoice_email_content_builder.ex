defmodule Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailContentBuilder do
  @moduledoc """
  Builds subject, text body, and HTML body for sales invoice emails.
  """

  use Phoenix.Component

  import Firmowid.Mailer.Components

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
    lang = content_language(invoice)

    subject =
      case lang do
        :pl -> "Faktura #{invoice_number}"
        :en -> "Invoice #{invoice_number}"
      end

    text =
      case lang do
        :pl ->
          """
          Dzień dobry,

          #{sender_pl}
          w załączniku przesyłamy fakturę #{invoice_number}.
          Termin płatności: #{due_date}.
          #{share_pl}
          """

        :en ->
          """
          Hello,

          #{sender_en}
          Attached is your invoice #{invoice_number}.
          Due date: #{due_date}.
          #{share_en}
          """
      end

    html =
      render_basic_html(lang, sender_pl, sender_en, invoice_number, due_date, share_pl, share_en)

    {subject, text, html}
  end

  def build(invoice, :reminder, share_url, _ash_opts) do
    {share_en, share_pl} = share_line(share_url)
    {sender_en, sender_pl} = sender_organization_line(invoice)
    invoice_number = invoice.invoice_number
    due_date = format_date(invoice.due_date)
    lang = content_language(invoice)

    subject =
      case lang do
        :pl -> "Przypomnienie o płatności: #{invoice_number}"
        :en -> "Payment Reminder: #{invoice_number}"
      end

    text =
      case lang do
        :pl ->
          """
          Dzień dobry,

          #{sender_pl}
          przypominamy o płatności dla faktury #{invoice_number}.
          Termin płatności: #{due_date}.
          #{share_pl}
          """

        :en ->
          """
          Hello,

          #{sender_en}
          this is a payment reminder for invoice #{invoice_number}.
          Due date: #{due_date}.
          #{share_en}
          """
      end

    html =
      render_reminder_html(
        lang,
        sender_pl,
        sender_en,
        invoice_number,
        due_date,
        share_pl,
        share_en
      )

    {subject, text, html}
  end

  def build(invoice, :invoice_correction, share_url, ash_opts) do
    {share_en, share_pl} = share_line(share_url)
    {sender_en, sender_pl} = sender_organization_line(invoice)

    {prev_number_en, prev_number_pl} =
      previous_invoice_number(SalesInvoiceChain.previous_invoice(invoice, ash_opts))

    invoice_number = invoice.invoice_number
    due_date = format_date(invoice.due_date)

    lang = content_language(invoice)

    subject =
      case lang do
        :pl -> "Korekta faktury #{prev_number_pl}"
        :en -> "Invoice Correction: #{prev_number_en}"
      end

    text =
      case lang do
        :pl ->
          """
          Dzień dobry,

          #{sender_pl}
          skorygowaliśmy fakturę #{prev_number_pl}. W załączniku przesyłamy fakturę korygującą #{invoice_number}.
          Termin płatności: #{due_date}.
          #{share_pl}
          """

        :en ->
          """
          Hello,

          #{sender_en}
          we have corrected invoice #{prev_number_en}. Attached is correcting invoice #{invoice_number}.
          Due date: #{due_date}.
          #{share_en}
          """
      end

    html =
      render_correction_html(%{
        lang: lang,
        sender_pl: sender_pl,
        sender_en: sender_en,
        prev_number_pl: prev_number_pl,
        prev_number_en: prev_number_en,
        invoice_number: invoice_number,
        due_date: due_date,
        share_pl: share_pl,
        share_en: share_en
      })

    {subject, text, html}
  end

  defp render_basic_html(:pl, sender_pl, _sender_en, invoice_number, due_date, share_pl, _share_en) do
    assigns = %{
      sender: sender_pl,
      invoice_number: invoice_number,
      due_date: due_date,
      share_url: share_pl
    }

    to_html(~H"""
    <.email preheader={"Faktura #{@invoice_number}"}>
      <.greeting>Faktura</.greeting>
      <.paragraph>
        {@sender}
      </.paragraph>
      <.paragraph>
        w załączniku przesyłamy fakturę <strong>{@invoice_number}</strong>.
      </.paragraph>
      <.paragraph>
        Termin płatności: <strong>{@due_date}</strong>.
      </.paragraph>
      <.paragraph :if={@share_url != ""}>
        {@share_url}
      </.paragraph>
      <.signature />
    </.email>
    """)
  end

  defp render_basic_html(:en, _sender_pl, sender_en, invoice_number, due_date, _share_pl, share_en) do
    assigns = %{
      sender: sender_en,
      invoice_number: invoice_number,
      due_date: due_date,
      share_url: share_en
    }

    to_html(~H"""
    <.email preheader={"Invoice #{@invoice_number}"}>
      <.greeting>Invoice</.greeting>
      <.paragraph>
        {@sender}
      </.paragraph>
      <.paragraph>
        Attached is your invoice <strong>{@invoice_number}</strong>.
      </.paragraph>
      <.paragraph>
        Due date: <strong>{@due_date}</strong>.
      </.paragraph>
      <.paragraph :if={@share_url != ""}>
        {@share_url}
      </.paragraph>
      <.signature />
    </.email>
    """)
  end

  defp render_reminder_html(:pl, sender_pl, _sender_en, invoice_number, due_date, share_pl, _share_en) do
    assigns = %{
      sender: sender_pl,
      invoice_number: invoice_number,
      due_date: due_date,
      share_url: share_pl
    }

    to_html(~H"""
    <.email preheader={"Przypomnienie o płatności: #{@invoice_number}"}>
      <.greeting>Przypomnienie o płatności</.greeting>
      <.paragraph>
        {@sender}
      </.paragraph>
      <.paragraph>
        przypominamy o płatności dla faktury <strong>{@invoice_number}</strong>.
      </.paragraph>
      <.paragraph>
        Termin płatności: <strong>{@due_date}</strong>.
      </.paragraph>
      <.paragraph :if={@share_url != ""}>
        {@share_url}
      </.paragraph>
      <.signature />
    </.email>
    """)
  end

  defp render_reminder_html(:en, _sender_pl, sender_en, invoice_number, due_date, _share_pl, share_en) do
    assigns = %{
      sender: sender_en,
      invoice_number: invoice_number,
      due_date: due_date,
      share_url: share_en
    }

    to_html(~H"""
    <.email preheader={"Payment Reminder: #{@invoice_number}"}>
      <.greeting>Payment Reminder</.greeting>
      <.paragraph>
        {@sender}
      </.paragraph>
      <.paragraph>
        this is a payment reminder for invoice <strong>{@invoice_number}</strong>.
      </.paragraph>
      <.paragraph>
        Due date: <strong>{@due_date}</strong>.
      </.paragraph>
      <.paragraph :if={@share_url != ""}>
        {@share_url}
      </.paragraph>
      <.signature />
    </.email>
    """)
  end

  defp render_correction_html(%{lang: :pl} = params) do
    assigns = %{
      sender: params.sender_pl,
      prev_number: params.prev_number_pl,
      invoice_number: params.invoice_number,
      due_date: params.due_date,
      share_url: params.share_pl
    }

    to_html(~H"""
    <.email preheader={"Korekta faktury #{@prev_number}"}>
      <.greeting>Korekta faktury</.greeting>
      <.paragraph>
        {@sender}
      </.paragraph>
      <.paragraph>
        skorygowaliśmy fakturę <strong>{@prev_number}</strong>. W załączniku przesyłamy fakturę korygującą <strong>{@invoice_number}</strong>.
      </.paragraph>
      <.paragraph>
        Termin płatności: <strong>{@due_date}</strong>.
      </.paragraph>
      <.paragraph :if={@share_url != ""}>
        {@share_url}
      </.paragraph>
      <.signature />
    </.email>
    """)
  end

  defp render_correction_html(%{lang: :en} = params) do
    assigns = %{
      sender: params.sender_en,
      prev_number: params.prev_number_en,
      invoice_number: params.invoice_number,
      due_date: params.due_date,
      share_url: params.share_en
    }

    to_html(~H"""
    <.email preheader={"Invoice Correction: #{@prev_number}"}>
      <.greeting>Invoice Correction</.greeting>
      <.paragraph>
        {@sender}
      </.paragraph>
      <.paragraph>
        we have corrected invoice <strong>{@prev_number}</strong>. Attached is correcting invoice <strong>{@invoice_number}</strong>.
      </.paragraph>
      <.paragraph>
        Due date: <strong>{@due_date}</strong>.
      </.paragraph>
      <.paragraph :if={@share_url != ""}>
        {@share_url}
      </.paragraph>
      <.signature />
    </.email>
    """)
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

  defp content_language(%{buyer_country: "PL"}), do: :pl
  defp content_language(_), do: :en
end
