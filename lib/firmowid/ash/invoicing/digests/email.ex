defmodule Firmowid.Ash.Invoicing.Digests.Email do
  @moduledoc """
  Transactional email delivery for KSeF invoice digests.

  Uses HTML email with inline styles for predictable client rendering.
  """

  use Phoenix.Component

  import Firmowid.Mailer.Components
  import Swoosh.Email

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Invoicing.RecommendationThresholds
  alias Firmowid.Mailer
  alias FirmowidWeb.Core.Endpoint

  @max_visible_invoices 3
  @max_visible_items 3

  @colors %{
    accent: "#8B3F13",
    dark: "#292929",
    grey: "#707070",
    light_grey: "#F5F5F5",
    white: "#FFFFFF",
    green_bg: "#D0E6CE",
    green_text: "#2B6B37",
    orange_bg: "#F4D5C6",
    orange_text: "#8B3F13",
    red_bg: "#F5D3D3",
    red_text: "#B42318"
  }

  @type invoice_summary :: %{
          optional(:suggestions_count) => non_neg_integer(),
          optional(:top_prediction_score) => float(),
          optional(:top_suggestions) => [map()],
          optional(:amount_placeholder) => String.t(),
          optional(:matched?) => boolean()
        }

  @spec deliver_ksef_invoice_digest(
          User.t() | map(),
          KsefInvoiceDigest.t() | map(),
          [CostInvoice.t() | map()],
          keyword()
        ) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_ksef_invoice_digest(user, digest, invoices, opts \\ []) do
    invoice_count = length(invoices)
    invoice_summaries = Keyword.get(opts, :invoice_summaries, %{})

    email =
      new()
      |> to(to_string(user.email))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject(digest_subject(invoice_count))
      |> html_body(html_email(digest, invoices, invoice_summaries))
      |> text_body(text_email(digest, invoices, invoice_summaries))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @spec render_html(KsefInvoiceDigest.t() | map(), [CostInvoice.t() | map()], keyword()) ::
          String.t()
  def render_html(digest, invoices, opts \\ []) do
    html_email(digest, invoices, Keyword.get(opts, :invoice_summaries, %{}))
  end

  @spec render_text(KsefInvoiceDigest.t() | map(), [CostInvoice.t() | map()], keyword()) ::
          String.t()
  def render_text(digest, invoices, opts \\ []) do
    text_email(digest, invoices, Keyword.get(opts, :invoice_summaries, %{}))
  end

  defp digest_subject(1), do: "Nowa faktura w Firmowidzie"
  defp digest_subject(count), do: "#{count} nowe faktury w Firmowidzie"

  defp html_email(_digest, invoices, invoice_summaries) do
    app_url = Endpoint.url()
    visible_invoices = Enum.take(invoices, @max_visible_invoices)
    remaining = length(invoices) - length(visible_invoices)
    single_invoice? = length(visible_invoices) == 1

    invoice_cards_html =
      Enum.map_join(visible_invoices, "", fn invoice ->
        summary = invoice_summary(invoice_summaries, invoice)
        invoice_card_html(invoice, summary, app_url, single_invoice?)
      end)

    remaining_html = remaining_html(remaining)

    assigns = %{
      headline: headline(length(invoices)),
      invoice_cards_html: invoice_cards_html,
      remaining_html: remaining_html,
      app_url: app_url
    }

    to_html(~H"""
    <.email preheader={@headline}>
      <.greeting>{@headline}</.greeting>
      <.paragraph>
        W Firmowidzie czekają nowe faktury z KSeF. Poniżej zobaczysz najważniejsze informacje,
        a resztę sprawdzisz po wejściu do aplikacji.
      </.paragraph>
      {Phoenix.HTML.raw(@invoice_cards_html)}
      {Phoenix.HTML.raw(@remaining_html)}
      <.button href={"#{@app_url}/fakturowanie"}>Otwórz faktury w Firmowidzie</.button>
      <.signature />
    </.email>
    """)
  end

  defp invoice_summary(invoice_summaries, invoice), do: Map.get(invoice_summaries, invoice.id, %{})

  defp headline(1), do: "Masz nową fakturę z KSeF"
  defp headline(count), do: "Masz #{count} #{new_invoice_phrase(count)} z KSeF"

  defp new_invoice_phrase(1), do: "nową fakturę"
  defp new_invoice_phrase(n) when n in 2..4, do: "nowe faktury"
  defp new_invoice_phrase(_n), do: "nowych faktur"

  defp text_invoice_noun(1), do: "faktura więcej"
  defp text_invoice_noun(n) when n in 2..4, do: "faktury więcej"
  defp text_invoice_noun(_n), do: "faktur więcej"

  defp transaction_match_noun(1), do: "możliwe dopasowanie transakcji"
  defp transaction_match_noun(n) when n in 2..4, do: "możliwe dopasowania transakcji"
  defp transaction_match_noun(_n), do: "możliwych dopasowań transakcji"

  defp invoice_seller(invoice), do: invoice.seller_display_name || invoice.seller || "(bez nazwy)"

  defp invoice_card_html(invoice, summary, app_url, single_invoice?) do
    table_width = if single_invoice?, do: "540px", else: "100%"
    left_width = if single_invoice?, do: "352px", else: "420px"
    amount_width = if single_invoice?, do: "132px", else: "152px"
    bottom_space = if single_invoice?, do: "128px", else: "148px"
    top_padding = if single_invoice?, do: "18px", else: "16px"

    """
    <table role="presentation" style="width:#{table_width}; border-collapse:collapse; margin:0 auto #{bottom_space} auto;">
      <tr>
        <td style="padding:0 0 16px 0; border-bottom:1px solid #ECECEC;">
          <table role="presentation" style="width:100%; border-collapse:collapse;">
            <tr>
              <td style="padding:0 16px 0 0; vertical-align:top; font-size:20px; line-height:1.3; color: #{@colors.dark}; font-weight:500;">
                #{invoice_seller(invoice)}
              </td>
              <td align="right" style="vertical-align:top; white-space:nowrap; font-size:15px; line-height:1.6;">
                <a href="#{app_url}/fakturowanie" style="color: #{@colors.accent}; text-decoration:none; font-weight:500;">
                  Otwórz w Firmowidzie →
                </a>
              </td>
            </tr>
          </table>
        </td>
      </tr>
      <tr>
        <td style="padding:#{top_padding} 0 0 0;">
          <table role="presentation" style="width:100%; border-collapse:collapse;">
            <tr>
              <td style="width:#{left_width}; padding:0 24px 0 0; vertical-align:top; font-size:15px; line-height:1.7; color: #{@colors.dark};">
                #{invoice_items_html(invoice)}
                #{recommendation_html(summary)}
              </td>
              <td align="right" valign="top" style="width:#{amount_width}; padding-top:10px; vertical-align:top; text-align:right; white-space:nowrap;">
                #{status_tag_html(summary)}
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
    """
  end

  defp invoice_items_html(invoice) do
    items = Map.get(invoice, :items_list, [])
    visible_items = Enum.take(items, @max_visible_items)
    remaining = length(items) - length(visible_items)

    items_html =
      Enum.map_join(visible_items, "", fn item ->
        name = Map.get(item, :name) || Map.get(item, "name") || "Pozycja bez nazwy"
        quantity = Map.get(item, :quantity) || Map.get(item, "quantity")

        quantity_suffix = if quantity, do: " × #{quantity}", else: ""

        """
        <table role=\"presentation\" style=\"margin:0 0 8px 0; border-collapse:collapse;\">
          <tr>
            <td style=\"width:14px; padding:0 8px 0 0; vertical-align:top;\">•</td>
            <td style=\"vertical-align:top;\">#{name}#{quantity_suffix}</td>
          </tr>
        </table>
        """
      end)

    remaining_html =
      if remaining > 0 do
        "<div style=\"margin:14px 0 0 0; color: #{@colors.grey};\">+ #{remaining} więcej</div>"
      else
        ""
      end

    if visible_items == [] do
      "<div style=\"color: #{@colors.grey};\">Brak pozycji do podglądu</div>"
    else
      items_html <> remaining_html <> ~s|<div style="height:12px;"></div>|
    end
  end

  defp recommendation_html(%{matched?: true}) do
    ""
  end

  defp recommendation_html(%{suggestions_count: count, top_suggestions: suggestions}) when count > 0 do
    """
    <div style="margin-top:22px; font-size:15px; line-height:1.6; color: #{@colors.dark};">
      Firmowid znalazł #{count} #{transaction_match_noun(count)}:
    </div>
    #{suggestion_rows_html(suggestions)}
    """
  end

  defp recommendation_html(_summary), do: ""

  defp transaction_icon_html(suggestion) do
    """
    <span style="display:inline-flex; width:28px; height:28px; background-color:#{suggestion.avatar_color || "#EFEFEF"}; border-radius:999px; align-items:center; justify-content:center; color: #{@colors.dark};">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" style="width:14px; height:14px; display:block;">
        <path d="M10.75 2.75a.75.75 0 0 0-1.5 0v.443a39.19 39.19 0 0 0-4.121 1.11A.75.75 0 0 0 4.5 5v1.756a33.147 33.147 0 0 1-1.728.549.75.75 0 0 0-.522.716V15.25H2a.75.75 0 0 0 0 1.5h16a.75.75 0 0 0 0-1.5h-.25V8.021a.75.75 0 0 0-.522-.716 32.429 32.429 0 0 1-1.728-.549V5a.75.75 0 0 0-.629-.697 39.22 39.22 0 0 0-4.121-1.11V2.75ZM6 6.08c1.5-.417 2.726-.707 4-.91 1.274.203 2.5.493 4 .91v9.17h-1.25v-3.5a.75.75 0 0 0-.75-.75h-4a.75.75 0 0 0-.75.75v3.5H6V6.08Zm2.75 9.17v-2.75h2.5v2.75h-2.5ZM6.5 8.5a.75.75 0 0 1 .75-.75h.008a.75.75 0 0 1 .75.75v.008a.75.75 0 0 1-.75.75H7.25a.75.75 0 0 1-.75-.75V8.5Zm0 2.5a.75.75 0 0 1 .75-.75h.008a.75.75 0 0 1 .75.75v.008a.75.75 0 0 1-.75.75H7.25a.75.75 0 0 1-.75-.75V11Zm5.5-2.5a.75.75 0 0 1 .75-.75h.008a.75.75 0 0 1 .75.75v.008a.75.75 0 0 1-.75.75h-.008a.75.75 0 0 1-.75-.75V8.5Zm0 2.5a.75.75 0 0 1 .75-.75h.008a.75.75 0 0 1 .75.75v.008a.75.75 0 0 1-.75.75h-.008a.75.75 0 0 1-.75-.75V11Z" />
      </svg>
    </span>
    """
  end

  defp suggestion_rows_html(suggestions) do
    Enum.map_join(suggestions, "", fn suggestion ->
      """
      <table role="presentation" style="margin-top:12px; border-collapse:collapse;">
        <tr>
          <td style="width:42px; padding:0; vertical-align:middle;">#{confidence_indicator_html(suggestion.score)}</td>
          <td style="width:120px; vertical-align:middle; font-size:15px; line-height:1.4; color: #{@colors.dark}; font-weight:500; white-space:nowrap;">
            #{RecommendationThresholds.to_percent(suggestion.score || 0.0)}% pewności
          </td>
          <td align="right" style="padding:0 0 0 18px; vertical-align:middle; white-space:nowrap;">
            <table role="presentation" style="margin-left:auto; border-collapse:collapse;">
              <tr>
                <td style="padding:0 10px 0 0; vertical-align:middle;">#{transaction_icon_html(suggestion)}</td>
                <td style="vertical-align:middle; font-size:15px; line-height:1.4; color: #{@colors.dark}; white-space:nowrap;">
                  #{suggestion.booking_date_label}
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
      """
    end)
  end

  defp confidence_indicator_html(score) do
    {bg_color, bar_colors} = active_confidence_indicator_colors(score)

    """
    <table role="presentation" style="width:28px; height:28px; background-color: #{bg_color}; border-radius:6px; border-collapse:separate; border-spacing:0;">
      <tr><td style="padding:4px 4px 0 4px;"><div style="height:2px; width:100%; background-color: #{elem(bar_colors, 0)};"></div></td></tr>
      <tr><td style="padding:0 4px;"><div style="height:2px; width:70%; background-color: #{elem(bar_colors, 1)};"></div></td></tr>
      <tr><td style="padding:0 4px 4px 4px;"><div style="height:2px; width:40%; background-color: #{elem(bar_colors, 2)};"></div></td></tr>
    </table>
    """
  end

  defp active_confidence_indicator_colors(score) do
    case RecommendationThresholds.prediction_level(score, true) do
      :high -> {@colors.green_bg, {@colors.green_text, @colors.green_text, @colors.green_text}}
      :mid -> {@colors.orange_bg, {@colors.white, @colors.orange_text, @colors.orange_text}}
      :low -> {@colors.red_bg, {@colors.white, @colors.white, @colors.red_text}}
    end
  end

  defp status_tag_html(%{matched?: true}) do
    ~s|<span style="display:inline-block; padding:4px 10px; border-radius:999px; background-color: #{@colors.green_bg}; color: #{@colors.green_text}; font-size:14px; line-height:1.4; font-weight:600;">dopasowane</span>|
  end

  defp status_tag_html(%{suggestions_count: count}) when count > 0 do
    ~s|<span style="display:inline-block; padding:4px 10px; border-radius:999px; background-color: #{@colors.red_bg}; color: #{@colors.red_text}; font-size:14px; line-height:1.4; font-weight:600;">niedopasowane</span>|
  end

  defp status_tag_html(_summary), do: ""

  defp remaining_html(remaining) when remaining > 0 do
    """
    <div style="padding:0 40px 32px 40px; text-align:center; font-size:15px; line-height:1.6; color: #{@colors.grey};">
      + #{remaining} #{text_invoice_noun(remaining)} czeka w Firmowidzie.
    </div>
    """
  end

  defp remaining_html(_remaining), do: ""

  defp text_email(_digest, [], _invoice_summaries) do
    """
    W Twojej organizacji pojawiły się nowe faktury kosztowe pobrane z KSeF.

    Wejdź na #{Endpoint.url()}/fakturowanie, aby zobaczyć szczegóły.
    """
  end

  defp text_email(_digest, invoices, invoice_summaries) do
    visible_invoices = Enum.take(invoices, @max_visible_invoices)
    remaining = length(invoices) - length(visible_invoices)

    body =
      Enum.map_join(visible_invoices, "\n\n", fn invoice ->
        summary = invoice_summary(invoice_summaries, invoice)

        [
          invoice_seller(invoice),
          text_items(invoice),
          text_recommendation(summary),
          text_amounts(summary),
          "Otwórz w Firmowidzie: #{Endpoint.url()}/fakturowanie"
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n")
      end)

    remaining_line =
      if remaining > 0,
        do: "\n\n+ #{remaining} #{text_invoice_noun(remaining)} czeka w Firmowidzie.",
        else: ""

    """
    #{headline(length(invoices))}

    #{body}#{remaining_line}

    Otwórz #{Endpoint.url()}/fakturowanie, aby zobaczyć szczegóły.
    """
  end

  defp text_items(invoice) do
    invoice
    |> Map.get(:items_list, [])
    |> Enum.take(@max_visible_items)
    |> Enum.map_join("\n", fn item ->
      name = Map.get(item, :name) || Map.get(item, "name") || "Pozycja bez nazwy"
      quantity = Map.get(item, :quantity) || Map.get(item, "quantity")
      quantity_suffix = if quantity, do: " × #{quantity}", else: ""
      "- #{name}#{quantity_suffix}"
    end)
  end

  defp text_recommendation(%{matched?: true}), do: "dopasowane"

  defp text_recommendation(%{suggestions_count: count, top_suggestions: suggestions}) when count > 0 do
    rows =
      Enum.map_join(suggestions, "\n", fn suggestion ->
        "💳 #{suggestion.booking_date_label} — #{RecommendationThresholds.to_percent(suggestion.score || 0.0)}% pewności"
      end)

    "niedopasowane\nFirmowid znalazł #{count} #{transaction_match_noun(count)}:\n#{rows}"
  end

  defp text_recommendation(_summary), do: nil

  defp text_amounts(_summary), do: nil
end
