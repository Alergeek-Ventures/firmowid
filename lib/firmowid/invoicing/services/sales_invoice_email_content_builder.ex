defmodule Firmowid.Invoicing.Services.SalesInvoiceEmailContentBuilder do
  @moduledoc """
  Builds subject, text body, and HTML body for sales invoice emails.

  The email goes to the seller's client, so it is written in the invoice's
  language (Polish for Polish buyers, English otherwise) rather than the UI
  locale, and it carries what the client needs to pay: the amount, the due
  date and the transfer details.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: FirmowidWeb.Core.Endpoint,
    router: FirmowidWeb.Core.Router

  import Firmowid.Mailer.Components
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.Services.SalesInvoiceChain

  @doc """
  Builds localized email content for a sales invoice delivery type.

  The invoice must have `:amount` loaded.
  """
  @spec build(SalesInvoice.t(), :basic | :reminder | :invoice_correction, String.t(), keyword()) ::
          {String.t(), String.t(), String.t()}
  def build(invoice, delivery_type, share_url, ash_opts) do
    lang = content_language(invoice)
    content = content(invoice, delivery_type, lang, share_url, ash_opts)
    {content.subject, text(content), to_html(html(content))}
  end

  defp content(invoice, delivery_type, lang, share_url, ash_opts) do
    seller = invoice.seller_display_name
    number = invoice.invoice_number

    # A correcting invoice's amount is the corrected total, not what is left to
    # pay, so emails about one (correction notices and their payment reminders)
    # leave amounts to the PDF.
    amount = if invoice.ksef_invoice_kind == :kor, do: nil, else: invoice.amount

    %{
      lang: lang,
      subject: subject(delivery_type, lang, number, invoice, ash_opts),
      headline: headline(delivery_type, lang, seller, number),
      lead: lead(delivery_type, lang, seller, number, invoice.buyer_display_name),
      amount: amount && Money.to_string!(amount, locale: lang),
      due_date: format_date(invoice.due_date),
      transfer: transfer(invoice, seller, lang),
      invoice_number: number,
      share_url: if(share_url in [nil, ""], do: nil, else: share_url),
      signup_url: url(~p"/zarejestruj")
    }
  end

  defp subject(:basic, :pl, number, _invoice, _opts), do: "Faktura #{number}"
  defp subject(:basic, :en, number, _invoice, _opts), do: "Invoice #{number}"

  defp subject(:reminder, :pl, number, _invoice, _opts), do: "Przypomnienie o płatności: #{number}"

  defp subject(:reminder, :en, number, _invoice, _opts), do: "Payment Reminder: #{number}"

  defp subject(:invoice_correction, lang, _number, invoice, ash_opts) do
    case {lang, previous_invoice_number(invoice, ash_opts)} do
      {:pl, nil} -> "Korekta faktury"
      {:pl, previous} -> "Korekta faktury #{previous}"
      {:en, nil} -> "Invoice Correction"
      {:en, previous} -> "Invoice Correction: #{previous}"
    end
  end

  defp previous_invoice_number(invoice, ash_opts) do
    case SalesInvoiceChain.previous_invoice(invoice, ash_opts) do
      %{invoice_number: number} when is_binary(number) -> number
      _previous -> nil
    end
  end

  defp headline(:basic, :pl, nil, number), do: "Faktura #{number}"
  defp headline(:basic, :pl, seller, _number), do: "Faktura od #{seller}"
  defp headline(:basic, :en, nil, number), do: "Invoice #{number}"
  defp headline(:basic, :en, seller, _number), do: "Invoice from #{seller}"

  defp headline(:reminder, :pl, _seller, number), do: "Przypomnienie o płatności za fakturę #{number}"

  defp headline(:reminder, :en, _seller, number), do: "Payment reminder for invoice #{number}"
  defp headline(:invoice_correction, :pl, _seller, number), do: "Faktura korygująca #{number}"
  defp headline(:invoice_correction, :en, _seller, number), do: "Correcting invoice #{number}"

  defp lead(:basic, :pl, _seller, _number, nil), do: "PDF jest w załączniku."

  defp lead(:basic, :pl, _seller, _number, buyer), do: "Wystawiona dla #{buyer}. PDF jest w załączniku."

  defp lead(:basic, :en, _seller, _number, nil), do: "The PDF is attached."
  defp lead(:basic, :en, _seller, _number, buyer), do: "Issued to #{buyer}. The PDF is attached."
  defp lead(_type, :pl, nil, _number, _buyer), do: "PDF jest w załączniku."
  defp lead(_type, :pl, seller, _number, _buyer), do: "Od #{seller}. PDF jest w załączniku."
  defp lead(_type, :en, nil, _number, _buyer), do: "The PDF is attached."
  defp lead(_type, :en, seller, _number, _buyer), do: "From #{seller}. The PDF is attached."

  defp transfer(%{payment_method: :transfer, seller_account_number: account} = invoice, seller, lang)
       when is_binary(account) and account != "" do
    account = if lang == :en, do: iban(account), else: account
    %{recipient: seller, account: account, title: invoice.invoice_number}
  end

  defp transfer(_invoice, _seller, _lang), do: nil

  # A transfer from abroad needs the full IBAN. Polish account numbers are often
  # stored as the bare 26-digit NRB, so the country code is added and the
  # number is grouped the way IBANs are printed.
  defp iban(account) do
    compact = String.replace(account, ~r/[^[:alnum:]]/, "")

    iban =
      if String.match?(compact, ~r/^\d{26}$/), do: "PL" <> compact, else: String.upcase(compact)

    iban
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  defp html(%{lang: :pl} = content) do
    assigns = %{
      content: content,
      copy: %{
        amount: "Do zapłaty (brutto)",
        due_date: "Termin płatności",
        button: "Zobacz fakturę",
        transfer: "Dane do przelewu",
        recipient: "Odbiorca",
        account: "Numer konta",
        title: "Tytuł przelewu",
        fallback: "Jeśli przycisk nie działa, otwórz link:"
      }
    }

    invoice_html(assigns)
  end

  defp html(%{lang: :en} = content) do
    assigns = %{
      content: content,
      copy: %{
        amount: "Amount due (gross)",
        due_date: "Due date",
        button: "View invoice",
        transfer: "Bank transfer details",
        recipient: "Recipient",
        account: "IBAN",
        title: "Transfer title",
        fallback: "If the button doesn't work, open this link:"
      }
    }

    invoice_html(assigns)
  end

  defp invoice_html(assigns) do
    ~H"""
    <.email preheader={preheader(@content)} lang={Atom.to_string(@content.lang)} figure={:invoice}>
      <:headline>{@content.headline}</:headline>
      <:lead>{@content.lead}</:lead>
      <.columns>
        <:left>
          <div :if={@content.amount}>
            <p style={"margin:0; font-family:#{font()}; font-size:13px; line-height:18px; color:#{pebble()};"}>
              {@copy.amount}
            </p>
            <p
              class="amount"
              style={"margin:6px 0 18px; font-family:#{font()}; font-size:36px; line-height:44px; font-weight:700; letter-spacing:-1px; color:#{ink()}; white-space:nowrap;"}
            >
              {@content.amount}
            </p>
          </div>
          <.field :if={@content.due_date} label={@copy.due_date}>
            <span style="font-size:20px; line-height:28px; font-weight:600;">{@content.due_date}</span>
          </.field>
          <.button :if={@content.share_url} href={@content.share_url} tone={:sales}>
            {@copy.button}
          </.button>
        </:left>
        <:right>
          <div :if={@content.transfer}>
            <p style={"margin:0 0 6px; font-family:#{font()}; font-size:13px; line-height:18px; font-weight:600; color:#455E5E;"}>
              {@copy.transfer}
            </p>
            <.field :if={@content.transfer.recipient} label={@copy.recipient}>
              {@content.transfer.recipient}
            </.field>
            <.field label={@copy.account}>
              <span
                :for={line <- account_lines(@content.transfer.account)}
                style="display:block; font-family:'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace;"
              >
                {line}
              </span>
            </.field>
            <.field label={@copy.title}>{@content.transfer.title}</.field>
          </div>
        </:right>
      </.columns>
      <:footer>
        <.note :if={@content.lang == :pl}>
          Fakturę wystawiono w Firmowidzie. Faktury z KSeF wystawisz w nim za darmo.
          <.link
            kind="unstyled"
            external={@content.signup_url}
            target="_blank"
            style={"color:#{ink()}; font-weight:600; text-decoration:underline; white-space:nowrap;"}
          >
            Załóż konto
          </.link>
        </.note>
        <.fallback_link :if={@content.share_url} href={@content.share_url} label={@copy.fallback} />
      </:footer>
    </.email>
    """
  end

  # A printed IBAN (34 characters) does not fit the 284px column on one line;
  # breaking it after the fourth group keeps the groups whole instead of
  # leaving the last one alone. A Polish NRB (32 characters) still fits.
  defp account_lines(account) when byte_size(account) > 32 do
    groups = String.split(account, " ")
    [groups |> Enum.take(4) |> Enum.join(" "), groups |> Enum.drop(4) |> Enum.join(" ")]
  end

  defp account_lines(account), do: [account]

  defp preheader(%{due_date: nil} = content), do: content.lead

  defp preheader(%{lang: :pl, amount: nil, due_date: due_date}), do: "Termin płatności #{due_date}."

  defp preheader(%{lang: :pl} = content), do: "#{content.amount}, termin płatności #{content.due_date}."

  defp preheader(%{lang: :en, amount: nil, due_date: due_date}), do: "Due date #{due_date}."
  defp preheader(%{lang: :en} = content), do: "#{content.amount}, due #{content.due_date}."

  defp text(%{lang: :pl} = content) do
    join_lines([
      content.headline,
      content.lead,
      "",
      content.amount && "Do zapłaty (brutto): #{content.amount}",
      content.due_date && "Termin płatności: #{content.due_date}",
      content.transfer &&
        "Numer konta: #{content.transfer.account}\nTytuł przelewu: #{content.transfer.title}",
      content.share_url && "\nZobacz fakturę: #{content.share_url}"
    ])
  end

  defp text(%{lang: :en} = content) do
    join_lines([
      content.headline,
      content.lead,
      "",
      content.amount && "Amount due (gross): #{content.amount}",
      content.due_date && "Due date: #{content.due_date}",
      content.transfer &&
        "IBAN: #{content.transfer.account}\nTransfer title: #{content.transfer.title}",
      content.share_url && "\nView invoice: #{content.share_url}"
    ])
  end

  defp join_lines(lines) do
    lines
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")
  defp format_date(nil), do: nil

  defp content_language(%{buyer_country: "PL"}), do: :pl
  defp content_language(_), do: :en
end
