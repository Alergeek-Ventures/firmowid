defmodule FirmowidWeb.Invoicing.Components.DashboardTiles do
  @moduledoc """
  Individual tile renderers for dashboard columns.

  Pattern-matches on `type` to render appropriate UI for:
  - unpaid invoices (cost/sales)
  - unmatched transactions
  - matched entries (with confidence badge)
  - suggestion tiles (bank connection, KSeF connection)
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.RecommendationThresholds
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  attr :entry, :any, required: true
  attr :type, :atom, required: true
  attr :return_to, :string, default: nil

  def tile(assigns) do
    ~H"""
    <div class="bg-lightGreyBg min-h-24 rounded-lg p-2.5 transition-shadow hover:shadow-sm">
      <%= case @type do %>
        <% :unpaid_invoice -> %>
          <.unpaid_invoice_tile entry={@entry} return_to={@return_to} />
        <% :unmatched_transaction -> %>
          <.unmatched_transaction_tile entry={@entry} return_to={@return_to} />
        <% :matched -> %>
          <.matched_entry_tile entry={@entry} return_to={@return_to} />
        <% :suggestion -> %>
          <.suggestion_tile entry={@entry} />
      <% end %>
    </div>
    """
  end

  # ── Unpaid Invoice Tile ────────────────────────────────────────────

  defp unpaid_invoice_tile(assigns) do
    entry = assigns.entry
    return_to = Map.get(assigns, :return_to)

    {party, invoice_number, amount, currency, navigate, issue_date} =
      extract_invoice_details(entry, return_to)

    {overdue_label, is_overdue} = format_due_date_status(entry)

    assigns =
      assigns
      |> assign(:party, party || "—")
      |> assign(:invoice_number, invoice_number || "—")
      |> assign(:amount, amount)
      |> assign(:currency, currency)
      |> assign(:navigate, navigate)
      |> assign(:issue_date, issue_date)
      |> assign(:overdue_label, overdue_label)
      |> assign(:is_overdue, is_overdue)

    ~H"""
    <.maybe_link navigate={@navigate} class="block">
      <div class="flex min-h-full flex-col gap-2">
        <div class="flex items-start justify-between gap-2">
          <span class="truncate text-sm font-medium">{@party}</span>
          <span class="text-sm font-semibold whitespace-nowrap">
            {format_money(@currency, @amount)}
          </span>
        </div>

        <div class="text-darkGrey text-xs">{@invoice_number}</div>

        <div class="mt-auto flex items-center justify-between gap-2 text-xs">
          <span class="text-grey-500">{format_date(@issue_date)}</span>

          <span
            :if={@overdue_label}
            class={[
              "flex items-center gap-1 font-medium",
              @is_overdue && "text-redText",
              not @is_overdue && "text-grey-600"
            ]}
          >
            <.icon :if={@is_overdue} name="hero-clock" class="size-3" />
            {@overdue_label}
          </span>
        </div>
      </div>
    </.maybe_link>
    """
  end

  defp extract_invoice_details(%CostInvoice{} = entry, return_to) do
    {
      entry.effective_seller_display_name,
      entry.invoice_identifier,
      entry.effective_total_amount,
      entry.effective_currency,
      Navigation.cost_invoice_show_path(entry, return_to),
      entry.issue_date
    }
  end

  defp extract_invoice_details(%SalesInvoice{} = entry, return_to) do
    {
      entry.buyer_display_name_label,
      entry.invoice_number,
      entry.gross_value,
      entry.currency,
      Navigation.sales_invoice_show_path(entry, return_to),
      entry.issue_date
    }
  end

  defp format_due_date_status(%CostInvoice{due_date: nil}), do: {nil, false}
  defp format_due_date_status(%SalesInvoice{due_date: nil}), do: {nil, false}

  defp format_due_date_status(%{due_date: due_date}) do
    today = Date.utc_today()
    days_diff = Date.diff(due_date, today)

    cond do
      days_diff < 0 -> {"#{abs(days_diff)} dni po terminie", true}
      days_diff == 0 -> {"Termin dzisiaj", true}
      days_diff <= 7 -> {"#{days_diff} dni do zapłaty", true}
      true -> {"Termin: #{format_date(due_date)}", false}
    end
  end

  # ── Unmatched Transaction Tile ─────────────────────────────────────

  defp unmatched_transaction_tile(assigns) do
    entry = assigns.entry
    party = transaction_party(entry)
    amount = entry.transaction_amount
    currency = entry.transaction_currency
    is_income = amount_positive?(amount)

    navigate = Navigation.transaction_show_path(entry, assigns.return_to)

    assigns =
      assigns
      |> assign(:party, party)
      |> assign(:amount, amount)
      |> assign(:currency, currency)
      |> assign(:booking_date, entry.booking_date)
      |> assign(:description, entry.remittance_information_unstructured)
      |> assign(:navigate, navigate)
      |> assign(:is_income, is_income)

    ~H"""
    <.transaction_tile_content
      party={@party || "—"}
      amount={@amount}
      currency={@currency}
      description={@description}
      booking_date={@booking_date}
      navigate={@navigate}
      is_income={@is_income}
    />
    """
  end

  attr :party, :string, required: true
  attr :amount, :any, required: true
  attr :currency, :any, required: true
  attr :booking_date, :any, required: true
  attr :navigate, :string, default: nil
  attr :is_income, :boolean, required: true
  attr :description, :string, default: nil

  defp transaction_tile_content(assigns) do
    ~H"""
    <.maybe_link navigate={@navigate} class="block">
      <div class="flex min-h-full flex-col gap-2">
        <div class="flex items-start justify-between gap-2">
          <span class="truncate text-sm font-medium">{@party}</span>
          <span class={[
            "flex items-center gap-1 text-sm font-semibold whitespace-nowrap",
            @is_income && "text-greenText",
            not @is_income && "text-redText"
          ]}>
            <.icon name={if @is_income, do: "hero-arrow-up", else: "hero-arrow-down"} class="size-3" />
            {format_money(@currency, decimal_abs(@amount))}
          </span>
        </div>

        <div :if={@description} class="text-darkGrey truncate text-xs">
          {@description}
        </div>

        <div class="mt-auto flex items-center text-xs">
          <span class="text-grey-500">{format_date(@booking_date)}</span>
        </div>
      </div>
    </.maybe_link>
    """
  end

  defp transaction_party(%Transaction{} = tx) do
    amount = tx.transaction_amount

    if amount_positive?(amount) do
      tx.debtor_name || "—"
    else
      tx.creditor_name || "—"
    end
  end

  defp transaction_party(_tx), do: "—"

  # ── Matched Entry Tile ────────────────────────────────────────────

  defp matched_entry_tile(assigns) do
    entry = assigns.entry

    {party, invoice_number, amount, currency, navigate, description} =
      matched_entry_details(entry, assigns.return_to)

    {badge_type, confidence_percent} = compute_confidence_badge(entry)

    assigns =
      assigns
      |> assign(:party, party || "—")
      |> assign(:invoice_number, invoice_number)
      |> assign(:amount, amount)
      |> assign(:currency, currency)
      |> assign(:navigate, navigate)
      |> assign(:description, description)
      |> assign(:badge_type, badge_type)
      |> assign(:confidence_percent, confidence_percent)

    ~H"""
    <.matched_tile_content
      party={@party}
      invoice_number={@invoice_number}
      amount={@amount}
      currency={@currency}
      navigate={@navigate}
      description={@description}
      badge_type={@badge_type}
      confidence_percent={@confidence_percent}
    />
    """
  end

  defp matched_entry_details(%CostInvoice{} = entry, return_to) do
    {
      entry.effective_seller_display_name,
      entry.invoice_identifier,
      entry.effective_total_amount,
      entry.effective_currency,
      Navigation.cost_invoice_show_path(entry, return_to),
      nil
    }
  end

  defp matched_entry_details(%{entry: entry}, return_to), do: matched_entry_details(entry, return_to)

  defp matched_entry_details(%SalesInvoice{} = entry, return_to) do
    {
      entry.buyer_display_name_label,
      entry.invoice_number,
      entry.gross_value,
      entry.currency,
      Navigation.sales_invoice_show_path(entry, return_to),
      nil
    }
  end

  defp matched_entry_details(%Transaction{} = entry, return_to) do
    {
      transaction_party(entry),
      nil,
      entry.transaction_amount,
      entry.transaction_currency,
      Navigation.transaction_show_path(entry, return_to),
      entry.remittance_information_unstructured
    }
  end

  attr :party, :string, required: true
  attr :invoice_number, :string, default: nil
  attr :amount, :any, required: true
  attr :currency, :any, required: true
  attr :navigate, :string, default: nil
  attr :badge_type, :atom, default: nil
  attr :confidence_percent, :integer, default: nil
  attr :description, :string, default: nil

  defp matched_tile_content(assigns) do
    ~H"""
    <.maybe_link navigate={@navigate} class="block">
      <div class="flex min-h-full flex-col gap-1">
        <div class="flex items-start justify-between gap-2">
          <span class="truncate text-sm font-medium">{@party}</span>
          <span class="text-sm font-semibold whitespace-nowrap">
            {format_money(@currency, @amount)}
          </span>
        </div>

        <div :if={@invoice_number} class="text-darkGrey mt-1 text-xs">{@invoice_number}</div>

        <div :if={@description} class="text-darkGrey mt-1 truncate text-xs">{@description}</div>

        <div :if={@badge_type} class="mt-auto">
          <.confidence_chip badge_type={@badge_type} confidence_percent={@confidence_percent} />
        </div>
      </div>
    </.maybe_link>
    """
  end

  # Pure logic function — returns {badge_type, confidence_percent} or {nil, nil}
  defp compute_confidence_badge(entry) do
    RecommendationThresholds.match_chip_type(
      Map.get(entry, :match_confidence, nil),
      Map.get(entry, :match_source, nil)
    )
  end

  # ── Confidence Chip Component ─────────────────────────────────────

  attr :badge_type, :atom, required: true
  attr :confidence_percent, :integer, required: true

  defp confidence_chip(%{badge_type: :manual} = assigns) do
    assigns = assign(assigns, :label, "Ręczne")

    ~H"""
    <div class="mt-2 flex items-center justify-start gap-2">
      <span class="bg-greenBg text-greenText inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-medium">
        <.icon name="hero-credit-card" class="size-3" />
        {@label}
      </span>
    </div>
    """
  end

  defp confidence_chip(%{badge_type: :high} = assigns) do
    assigns = assign(assigns, :label, "#{assigns.confidence_percent}% pewności")

    ~H"""
    <div class="mt-2 flex items-center justify-start gap-2">
      <span class="bg-greenBg text-greenText inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-medium">
        <.icon name="hero-credit-card" class="size-3" />
        {@label}
      </span>
    </div>
    """
  end

  defp confidence_chip(%{badge_type: :mid} = assigns) do
    assigns = assign(assigns, :label, "#{assigns.confidence_percent}% pewności")

    ~H"""
    <div class="mt-2 flex items-center justify-start gap-2">
      <span class="inline-flex items-center gap-1 rounded-full bg-orange-100 px-2 py-1 text-[11px] font-medium text-orange-600">
        <.icon name="hero-credit-card" class="size-3" />
        {@label}
      </span>
    </div>
    """
  end

  defp confidence_chip(%{badge_type: :low} = assigns) do
    assigns = assign(assigns, :label, "#{assigns.confidence_percent}% pewności")

    ~H"""
    <div class="mt-2 flex items-center justify-between gap-2">
      <span class="bg-redBg text-redText inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-medium">
        <.icon name="hero-credit-card" class="size-3" />
        {@label}
      </span>

      <.button type="button" variant="secondary" size="small" class="text-[11px]">
        Sprawdź
      </.button>
    </div>
    """
  end

  defp confidence_chip(%{badge_type: _} = assigns) do
    # :unknown or any other value — keep simple neutral chip
    assigns = assign(assigns, :label, "#{assigns.confidence_percent}% pewności")

    ~H"""
    <div class="mt-2 flex items-center justify-start gap-2">
      <span class="bg-grey-200 text-darkGrey inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-medium">
        <.icon name="hero-credit-card" class="size-3" />
        {@label}
      </span>
    </div>
    """
  end

  # ── Suggestion Tile ───────────────────────────────────────────────

  defp suggestion_tile(%{entry: %{type: :missing_invoice, client_name: client_name, amount: amount}} = assigns) do
    assigns = assign(assigns, :client_name, client_name)
    assigns = assign(assigns, :amount, amount)

    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <div class="bg-grey-200 flex size-6 items-center justify-center rounded">
            <.icon name="hero-document-text" class="text-grey-600 size-4" />
          </div>
          <span class="text-sm font-medium">Brak faktury</span>
        </div>
        <span class="text-sm font-semibold whitespace-nowrap">{format_money(nil, @amount)}</span>
      </div>

      <p class="text-grey-600 text-xs">
        <span class="font-medium">{@client_name}</span>
        {" "}płaci cyklicznie - w tym miesiącu wykryliśmy brak faktury.
      </p>

      <.link
        navigate={~p"/sprzedazowe/nowa"}
        kind="button"
        variant="secondary"
        size="small"
        class="mt-1 w-full"
      >
        Wystaw fakturę
      </.link>
    </div>
    """
  end

  defp suggestion_tile(%{entry: %{type: :missing_payment, client_name: client_name, amount: amount}} = assigns) do
    assigns = assign(assigns, :client_name, client_name)
    assigns = assign(assigns, :amount, amount)

    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <div class="bg-grey-200 flex size-6 items-center justify-center rounded">
            <.icon name="hero-banknotes" class="text-grey-600 size-4" />
          </div>
          <span class="text-sm font-medium">Cykliczna płatność</span>
        </div>
        <span class="text-sm font-semibold whitespace-nowrap">{format_money(nil, @amount)}</span>
      </div>

      <p class="text-grey-600 text-xs">
        Płacisz regularnie firmie <span class="font-medium">{@client_name}</span>, w tym miesiącu nie wykryliśmy jeszcze transakcji.
      </p>

      <div class={suggestion_action_styles()}>
        Zapłać
      </div>
    </div>
    """
  end

  defp suggestion_tile(%{entry: %{type: :connect_bank}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex items-center gap-2">
        <div class="bg-blueBg flex size-6 items-center justify-center rounded">
          <.icon name="hero-building-library" class="text-blueText size-4" />
        </div>
        <span class="text-sm font-medium">Podepnij konto bankowe</span>
      </div>

      <p class="text-grey-600 text-xs">Transakcje pojawią się automatycznie po podłączeniu konta.</p>

      <.link
        navigate={~p"/ustawienia/bank/dodaj"}
        kind="button"
        variant="secondary"
        size="small"
        class="mt-1 w-full"
      >
        Połącz bank
      </.link>
    </div>
    """
  end

  defp suggestion_tile(%{entry: %{type: :connect_ksef}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <div class="flex items-center gap-2">
        <div class="bg-greenBg flex size-6 items-center justify-center rounded">
          <.icon name="hero-document-arrow-up-solid" class="text-greenText size-4" />
        </div>
        <span class="text-sm font-medium">Połącz z KSeF</span>
      </div>

      <p class="text-grey-600 text-xs">
        Faktury będą automatycznie wysyłane do Krajowego Systemu e-Faktur.
      </p>

      <.link
        navigate={~p"/ustawienia/firma"}
        kind="button"
        variant="secondary"
        size="small"
        class="mt-1 w-full"
      >
        Połącz KSeF
      </.link>
    </div>
    """
  end

  defp suggestion_tile(%{entry: entry} = assigns) do
    title = Map.get(entry, :title, "Sugestia")
    description = Map.get(entry, :description, "Szczegóły sugestii nie są dostępne.")

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:description, description)

    ~H"""
    <div class="flex flex-col gap-2">
      <div class="text-sm font-medium">{@title}</div>
      <p class="text-grey-600 text-xs">{@description}</p>
    </div>
    """
  end

  # ── Shared helpers ────────────────────────────────────────────────

  attr :navigate, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp maybe_link(assigns) do
    ~H"""
    <.link :if={@navigate} kind="unstyled" navigate={@navigate} class={@class}>
      {render_slot(@inner_block)}
    </.link>

    <div :if={is_nil(@navigate)} class={@class}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp format_money(_currency, amount) when is_nil(amount), do: "—"

  defp format_money(nil, amount) when not is_nil(amount) do
    Money.new(:PLN, amount)
  rescue
    _ -> "—"
  end

  defp format_money(currency, amount) do
    Money.new(currency, amount)
  rescue
    _ -> "—"
  end

  defp amount_positive?(nil), do: false

  defp amount_positive?(amount) when is_integer(amount), do: amount > 0

  defp amount_positive?(%Decimal{} = amount), do: Decimal.gt?(amount, 0)

  defp decimal_abs(nil), do: nil

  defp decimal_abs(amount) when is_integer(amount), do: abs(amount)

  defp decimal_abs(%Decimal{} = amount), do: Decimal.abs(amount)

  defp format_date(nil), do: ""

  defp format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp suggestion_action_styles do
    "bg-greyButtonBg text-darkGrey mt-1 block w-full rounded-md px-3 py-2 text-center text-xs font-medium transition-colors hover:bg-grey-300"
  end
end
