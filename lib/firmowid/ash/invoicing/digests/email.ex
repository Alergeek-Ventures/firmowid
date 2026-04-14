defmodule Firmowid.Ash.Invoicing.Digests.Email do
  @moduledoc """
  Transactional email delivery for KSeF invoice digests.

  Uses HTML email with inline styles (Tailwind-inspired) for consistent
  rendering across email clients.
  """

  import Swoosh.Email

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Mailer
  alias FirmowidWeb.Core.Endpoint

  # Brand colors from app.css
  # Cost invoices use orange theme, action buttons are black
  @colors %{
    cost_text: "#8B3F13",
    button_bg: "#000000",
    dark: "#4E4E4E",
    grey: "#707070",
    light_grey: "#F5F5F5",
    white: "#FFFFFF",
    border: "#DDDDDD"
  }

  @doc """
  Delivers a KSeF cost-invoice digest to a single admin user.
  """
  @spec deliver_ksef_invoice_digest(User.t() | map(), KsefInvoiceDigest.t() | map(), [
          CostInvoice.t() | map()
        ]) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_ksef_invoice_digest(user, digest, invoices) do
    invoice_count = length(invoices)

    email =
      new()
      |> to(to_string(user.email))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject(digest_subject(invoice_count))
      |> html_body(html_email(user, digest, invoices))
      |> text_body(text_email(user, digest, invoices))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp digest_subject(1), do: "Nowa faktura w Firmowidzie"
  defp digest_subject(count), do: "#{count} nowe faktury w Firmowidzie"

  defp html_email(user, _digest, invoices) do
    logo_url = "#{Endpoint.url()}/images/logo_firmowid.png"
    app_url = Endpoint.url()

    """
    <!DOCTYPE html>
    <html lang="pl">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Nowe faktury KSeF</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Lexend:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    </head>
    <body style="margin: 0; padding: 0; background-color: #{@colors.light_grey}; font-family: 'Lexend', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
      <table role="presentation" style="width: 100%; border-collapse: collapse;">
        <tr>
          <td align="center" style="padding: 40px 20px;">
            <!-- Main Container -->
            <table role="presentation" style="width: 100%; max-width: 600px; border-collapse: collapse; background-color: #{@colors.white}; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.08);">

              <!-- Header with Logo -->
              <tr>
                <td style="padding: 32px 40px 24px 40px; text-align: center;">
                  <img src="#{logo_url}" alt="Firmowid" style="height: 40px; width: auto;">
                </td>
              </tr>

              <!-- Greeting -->
              <tr>
                <td style="padding: 32px 40px 24px 40px;">
                  <p style="margin: 0; font-size: 16px; color: #{@colors.grey}; line-height: 1.6;">
                    Cześć #{user.name || user.email},
                  </p>
                  <p style="margin: 12px 0 0 0; font-size: 16px; color: #{@colors.grey}; line-height: 1.6;">
                    W Twojej organizacji pojawiły się nowe faktury kosztowe pobrane z KSeF.
                  </p>
                </td>
              </tr>

              <!-- Invoices List -->
              #{invoices_list_html(invoices, app_url)}

              <!-- Action Button -->
              <tr>
                <td style="padding: 32px 40px; text-align: center;">
                  <a href="#{app_url}/kosztowe"
                     style="display: inline-block; background-color: #{@colors.button_bg}; color: #{@colors.white}; padding: 16px 32px; border-radius: 6px; text-decoration: none; font-size: 16px; font-weight: 600; transition: background-color 0.3s;">
                    #{button_text(invoices)}
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  # Maximum number of invoices to show in email
  @max_visible_invoices 2

  defp invoices_list_html(invoices, app_url) do
    visible_invoices = Enum.take(invoices, @max_visible_invoices)

    invoices_html =
      Enum.map_join(visible_invoices, "\n", fn invoice ->
        total_amount = invoice.total_amount |> Decimal.abs() |> Decimal.to_string(:normal)

        """
        <!-- Invoice Card -->
        <tr>
          <td style="padding: 8px 40px;">
            <table role="presentation" style="width: 100%; border: 1px solid #{@colors.border}; border-radius: 6px; background-color: #{@colors.white};">
              <tr>
                <td style="padding: 20px;">
                  <table role="presentation" style="width: 100%;">
                    <tr>
                      <td style="padding-bottom: 12px;">
                        <p style="margin: 0; font-size: 14px; font-weight: 600; color: #{@colors.cost_text};">
                           #{invoice.seller_display_name}
                         </p>
                      </td>
                      <td style="text-align: right; padding-bottom: 12px;">
                        <p style="margin: 0; font-size: 18px; font-weight: 600; color: #{@colors.dark};">
                          #{total_amount} #{invoice.currency}
                        </p>
                      </td>
                    </tr>
                    <tr>
                      <td colspan="2" style="padding-top: 16px;">
                       <a href="#{app_url}/kosztowe/#{invoice.id}"
                            style="display: inline-block; color: #{@colors.cost_text}; text-decoration: none; font-size: 13px; font-weight: 500;">
                            Zobacz szczegóły →
                          </a>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        """
      end)

    """
    <!-- Invoices Section -->
    <tr>
      <td style="padding: 8px 0 16px 0;">
        #{invoices_html}
      </td>
    </tr>
    """
  end

  defp button_text(invoices) do
    total_count = length(invoices)
    remaining = total_count - @max_visible_invoices

    cond do
      remaining <= 0 ->
        "Zobacz w Firmowidzie"

      remaining == 1 ->
        "Zobacz 1 fakturę więcej w Firmowidzie"

      remaining in 2..4 ->
        "Zobacz #{remaining} faktury więcej w Firmowidzie"

      true ->
        "Zobacz #{remaining} faktur więcej w Firmowidzie"
    end
  end

  defp text_email(user, _digest, [invoice]) do
    """
    Cześć #{user.name || user.email},

    Masz nową fakturę z KSeF!

    Od #{invoice.seller_display_name}, na kwotę #{invoice.total_amount}.

    Wejdź na #{Endpoint.url()}/kosztowe, aby zobaczyć szczegóły.
    """
  end

  defp text_email(user, _digest, [first | _rest] = invoices) do
    remaining = length(invoices) - 1

    """
    Cześć #{user.name || user.email},

    Masz nowe faktury z KSeF!

    Od #{first.seller_display_name}, na kwotę #{first.total_amount}.

    Oraz #{remaining} #{text_invoice_noun(remaining)}!

    Wejdź na #{Endpoint.url()}/kosztowe, aby zobaczyć wszystkie nowe faktury.
    """
  end

  defp text_invoice_noun(1), do: "faktura więcej"
  defp text_invoice_noun(n) when n in 2..4, do: "faktury więcej"
  defp text_invoice_noun(_n), do: "faktur więcej"
end
