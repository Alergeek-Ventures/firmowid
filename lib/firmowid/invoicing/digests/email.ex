defmodule Firmowid.Invoicing.Digests.Email do
  @moduledoc """
  Transactional email delivery for KSeF invoice digests.

  The digest never shows invoice amounts: the owner opens Firmowid for those.
  """

  use Phoenix.Component

  import Firmowid.Mailer.Components
  import Swoosh.Email, except: [assign: 3]

  alias Firmowid.Core.User
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.KsefInvoiceDigest
  alias Firmowid.Invoicing.RecommendationThresholds
  alias Firmowid.Mailer
  alias FirmowidWeb.Core.Endpoint

  @max_visible_invoices 3
  @max_visible_items 3

  @status_colors %{
    matched: %{background: "#D0E6CE", text: "#2D432B"},
    unmatched: %{background: "#E6D7CE", text: "#4E2005"}
  }

  @score_colors %{high: "#475E45", mid: "#8B3F13", low: "#A22A2A"}

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

  defp digest_subject(count),
    do: "#{count} #{polish_form(count, "nowa faktura", "nowe faktury", "nowych faktur")} w Firmowidzie"

  defp html_email(_digest, invoices, invoice_summaries) do
    visible =
      invoices
      |> Enum.take(@max_visible_invoices)
      |> Enum.map(&row(&1, invoice_summary(invoice_summaries, &1)))

    assigns = %{
      headline: headline(length(invoices)),
      rows: visible,
      remaining: length(invoices) - length(visible),
      url: Endpoint.url() <> "/fakturowanie"
    }

    to_html(~H"""
    <.email preheader={preheader(@rows, @remaining)} figure={:invoice}>
      <:headline>{@headline}</:headline>
      <%= case @rows do %>
        <% [row] -> %>
          <.columns>
            <:left><.invoice_heading row={row} /></:left>
            <:right>
              <.status_pill matched?={row.matched?} />
              <.suggestion_list suggestions={row.suggestions} />
            </:right>
          </.columns>
        <% rows -> %>
          <table
            role="presentation"
            width="100%"
            cellspacing="0"
            cellpadding="0"
            border="0"
            style="border-collapse:collapse;"
          >
            <tr :for={row <- rows}>
              <td style={"border-bottom:1px solid #{line()}; padding:16px 0;"}>
                <.columns>
                  <:left><.invoice_heading row={row} /></:left>
                  <:right>
                    <.status_pill matched?={row.matched?} />
                    <.suggestion_line suggestions={row.suggestions} />
                  </:right>
                </.columns>
              </td>
            </tr>
          </table>
      <% end %>
      <p
        :if={@remaining > 0}
        style={"margin:16px 0 0; font-family:#{font()}; font-size:14px; line-height:20px; color:#{graphite()};"}
      >
        {remaining_line(@remaining)}
      </p>
      <.button href={@url} tone={:cost}>
        {if length(@rows) == 1, do: "Otwórz w Firmowidzie", else: "Otwórz faktury w Firmowidzie"}
      </.button>
      <:footer>
        <.fallback_link href={@url} />
      </:footer>
    </.email>
    """)
  end

  defp row(invoice, summary) do
    items = Map.get(invoice, :items_list, [])

    %{
      seller: invoice_seller(invoice),
      items: items |> Enum.take(@max_visible_items) |> Enum.map(&item_label/1),
      more_items: max(length(items) - @max_visible_items, 0),
      matched?: Map.get(summary, :matched?, false),
      suggestions: suggestions(summary)
    }
  end

  defp suggestions(%{matched?: true}), do: []
  defp suggestions(summary), do: Map.get(summary, :top_suggestions, [])

  defp invoice_summary(invoice_summaries, invoice), do: Map.get(invoice_summaries, invoice.id, %{})

  defp headline(1), do: "Masz nową fakturę z KSeF"

  defp headline(count), do: "Masz #{count} #{polish_form(count, "nową fakturę", "nowe faktury", "nowych faktur")} z KSeF"

  defp remaining_line(count) do
    verb = polish_form(count, "czeka", "czekają", "czeka")

    "Jeszcze #{count} #{polish_form(count, "faktura", "faktury", "faktur")} #{verb} w Firmowidzie."
  end

  defp preheader(rows, 0), do: rows |> Enum.map_join(", ", & &1.seller) |> Kernel.<>(".")

  defp preheader(rows, remaining) do
    "#{Enum.map_join(rows, ", ", & &1.seller)} i jeszcze #{remaining}."
  end

  defp invoice_seller(invoice), do: invoice.seller_display_name || invoice.seller || "(bez nazwy)"

  defp item_label(item) do
    name = Map.get(item, :name) || Map.get(item, "name") || "Pozycja bez nazwy"
    quantity = Map.get(item, :quantity) || Map.get(item, "quantity")
    if quantity, do: "#{name} × #{quantity}", else: name
  end

  attr :row, :map, required: true

  defp invoice_heading(assigns) do
    ~H"""
    <p style={"margin:0; font-family:#{font()}; font-size:16px; line-height:22px; font-weight:600; color:#{ink()};"}>
      {@row.seller}
    </p>
    <p
      :for={item <- @row.items}
      style={"margin:6px 0 0; font-family:#{font()}; font-size:14px; line-height:20px; color:#{graphite()};"}
    >
      {item}
    </p>
    <p
      :if={@row.items == []}
      style={"margin:6px 0 0; font-family:#{font()}; font-size:14px; line-height:20px; color:#{pebble()};"}
    >
      Brak pozycji do podglądu
    </p>
    <p
      :if={@row.more_items > 0}
      style={"margin:6px 0 0; font-family:#{font()}; font-size:14px; line-height:20px; color:#{pebble()};"}
    >
      + {@row.more_items} więcej
    </p>
    """
  end

  attr :matched?, :boolean, required: true

  defp status_pill(assigns) do
    assigns =
      assign(
        assigns,
        :colors,
        @status_colors[if(assigns.matched?, do: :matched, else: :unmatched)]
      )

    ~H"""
    <span style={"display:inline-block; padding:3px 10px; border-radius:999px; background:#{@colors.background}; color:#{@colors.text}; font-family:#{font()}; font-size:13px; line-height:18px; font-weight:600; white-space:nowrap;"}>
      {if @matched?, do: "dopasowane", else: "niedopasowane"}
    </span>
    """
  end

  attr :suggestions, :list, required: true

  defp suggestion_list(assigns) do
    ~H"""
    <div :if={@suggestions != []} style="margin-top:16px;">
      <p style={"margin:0 0 4px; font-family:#{font()}; font-size:13px; line-height:18px; color:#{pebble()};"}>
        {if length(@suggestions) == 1, do: "Możliwy przelew", else: "Możliwe przelewy"}
      </p>
      <table
        role="presentation"
        width="100%"
        cellspacing="0"
        cellpadding="0"
        border="0"
        style="border-collapse:collapse;"
      >
        <tr :for={{suggestion, index} <- Enum.with_index(@suggestions)}>
          <td style={"padding:8px 0; #{row_border(index)} font-family:#{font()}; font-size:14px; line-height:20px; color:#{ink()};"}>
            {suggestion.booking_date_label}
          </td>
          <td
            align="right"
            style={"padding:8px 0; #{row_border(index)} font-family:#{font()}; font-size:14px; line-height:20px; font-weight:600; color:#{score_color(suggestion.score)};"}
          >
            {percent(suggestion.score)}%
          </td>
        </tr>
      </table>
    </div>
    """
  end

  attr :suggestions, :list, required: true

  defp suggestion_line(assigns) do
    ~H"""
    <p
      :if={@suggestions != []}
      style={"margin:6px 0 0; font-family:#{font()}; font-size:13px; line-height:18px; color:#{pebble()};"}
    >
      {suggestion_summary(@suggestions)}
    </p>
    """
  end

  defp suggestion_summary([best | others]) do
    base = "Możliwy przelew: #{best.booking_date_label} (#{percent(best.score)}%)"

    case length(others) do
      0 -> base
      count -> "#{base}, +#{count} #{polish_form(count, "inny", "inne", "innych")}"
    end
  end

  defp row_border(0), do: ""
  defp row_border(_index), do: "border-top:1px solid #{line()};"

  defp percent(score), do: RecommendationThresholds.to_percent(score || 0.0)

  defp score_color(score), do: @score_colors[RecommendationThresholds.prediction_level(score, true)]

  defp text_email(_digest, [], _invoice_summaries) do
    """
    W Twojej organizacji pojawiły się nowe faktury kosztowe pobrane z KSeF.

    Wejdź na #{Endpoint.url()}/fakturowanie, aby zobaczyć szczegóły.
    """
  end

  defp text_email(_digest, invoices, invoice_summaries) do
    visible = Enum.take(invoices, @max_visible_invoices)
    remaining = length(invoices) - length(visible)

    body =
      Enum.map_join(visible, "\n\n", fn invoice ->
        row = row(invoice, invoice_summary(invoice_summaries, invoice))

        [
          row.seller,
          Enum.map_join(row.items, "\n", &"- #{&1}"),
          if(row.matched?, do: "dopasowane", else: "niedopasowane"),
          text_suggestions(row.suggestions)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n")
      end)

    remaining_line = if remaining > 0, do: "\n\n" <> remaining_line(remaining), else: ""

    """
    #{headline(length(invoices))}

    #{body}#{remaining_line}

    Otwórz w Firmowidzie: #{Endpoint.url()}/fakturowanie
    """
  end

  defp text_suggestions([]), do: nil

  defp text_suggestions(suggestions) do
    label = if length(suggestions) == 1, do: "Możliwy przelew:", else: "Możliwe przelewy:"

    rows = Enum.map_join(suggestions, "\n", &"- #{&1.booking_date_label}, #{percent(&1.score)}%")

    "#{label}\n#{rows}"
  end

  defp polish_form(1, one, _few, _many), do: one
  defp polish_form(count, _one, _few, many) when rem(count, 100) in 12..14, do: many
  defp polish_form(count, _one, few, _many) when rem(count, 10) in 2..4, do: few
  defp polish_form(_count, _one, _few, many), do: many
end
