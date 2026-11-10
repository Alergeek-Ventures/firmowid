defmodule FirmowidWeb.Assistant.Components.Invoice do
  @moduledoc """
  The invoice an assistant preview prepared, in two sizes showing one state: a small card in the
  conversation and the shared confirmation widget in a panel beside it. The assistant LiveView
  owns the `FirmowidUI.Invoicing.Issuance` and handles the events.
  """
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidUI.Invoicing.Components.Issuance, as: IssuanceWidget
  alias FirmowidUI.Invoicing.Components.SalesInvoice, as: InvoicePreview
  alias FirmowidUI.Invoicing.Issuance
  alias FirmowidWeb.Assistant.Components.Records
  alias Phoenix.LiveView.Rendered

  attr :id, :string, required: true, doc: "The preview's tool call."
  attr :issuance, Issuance, required: true
  attr :open?, :boolean, required: true, doc: "Whether the panel shows this invoice."
  attr :dismissed?, :boolean, required: true

  @doc "Renders the card: thumbnail, buyer, items, totals and dates, then confirmation or its result."
  @spec card(map()) :: Rendered.t()
  def card(%{dismissed?: true} = assigns) do
    ~H"""
    <p id={"assistant-invoice-#{@id}"} class="flex items-center gap-2 text-sm text-grey-600">
      <Lucideicons.x class="size-4" aria-hidden="true" />{rejected_label(@issuance)}
    </p>
    """
  end

  def card(assigns) do
    assigns = assign(assigns, invoice: assigns.issuance.invoice)

    ~H"""
    <section
      id={"assistant-invoice-#{@id}"}
      class={[
        "@container grid grid-cols-[auto_minmax(0,1fr)] items-start gap-x-4 rounded-lg border ps-3 pe-4 pbs-3 pbe-3.5 @max-[27.5rem]:grid-cols-1 @max-[27.5rem]:ps-4",
        if(@open?, do: "border-grey-400", else: "border-grey-200")
      ]}
      aria-label={title(@issuance)}
    >
      <Button.button
        :if={@invoice}
        type="button"
        variant="unstyled"
        class="block cursor-zoom-in overflow-clip rounded-sm border border-grey-200 bg-white p-0 shadow-sm block-41 inline-30 @max-[27.5rem]:hidden pointer-fine:hover:border-grey-500"
        phx-click="invoice_open"
        phx-value-call={@id}
        aria-label={gettext("Open the invoice preview")}
      >
        <div class="pointer-events-none zoom-[.2]" aria-hidden="true">
          <InvoicePreview.sales_invoice
            sales_invoice={Map.put(@invoice, :buyer_pesel, nil)}
            currency_rate={@issuance.currency_rate}
            show_vat={@issuance.show_vat}
            reference_invoice={@invoice.reference_invoice}
            footer_logo_data_uri={~p"/images/invoice_firmowid_logo.png"}
          />
        </div>
      </Button.button>
      <div class={["flex flex-col gap-2 pbs-0.5 min-inline-0", !@invoice && "col-span-full"]}>
        <div class="flex items-start justify-between gap-3">
          <div class="min-inline-0">
            <h3 class="text-sm/snug font-semibold text-grey-900">{title(@issuance)}</h3>
            <p :if={@invoice} class="text-sm wrap-anywhere text-grey-600">{buyer(@issuance)}</p>
          </div>
          <Button.button
            :if={@invoice}
            type="button"
            variant="outline"
            size="small"
            class="pointer-coarse:min-block-11"
            phx-click="invoice_open"
            phx-value-call={@id}
            aria-expanded={to_string(@open?)}
            aria-controls="assistant-invoice-panel"
          >
            <Lucideicons.panel_right class="size-4" aria-hidden="true" />
            {if @open?, do: gettext("Hide"), else: gettext("Preview")}
          </Button.button>
        </div>
        <%= if @invoice do %>
          <div class="flex flex-col divide-y divide-grey-200 border-y border-grey-200">
            <Records.row
              :for={item <- items(@issuance)}
              amount={Money.new(@invoice.currency, item.gross)}
              amount_tone={:income}
            >
              <:title>{item.name}</:title>
              <:meta>
                {gettext("%{quantity} %{unit} × %{price} net",
                  quantity: item.quantity,
                  unit: item.unit,
                  price: item.price
                )}
              </:meta>
            </Records.row>
          </div>
          <div class="flex items-baseline justify-between gap-3 font-medium text-grey-900">
            <span>
              {total_label(@issuance)}
              <small class="block text-xs font-normal text-grey-600">{total_details(@issuance)}</small>
            </span>
            <span class="text-base font-semibold text-nowrap tabular-nums">
              {Money.new(@invoice.currency, @invoice.gross_value)}
            </span>
          </div>
          <p class="text-sm text-grey-600">{dates(@issuance)}</p>
        <% end %>
        <p :for={error <- @issuance.errors} role="alert" class="text-sm text-brick-700">{error}</p>
        <.result issuance={@issuance} id={@id} />
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :issuance, Issuance, required: true

  defp result(%{issuance: %{phase: :review}} = assigns) do
    ~H"""
    <%!-- One row at every width: a narrow card makes the labels smaller instead of wrapping. --%>
    <div :if={@issuance.invoice} class="mbs-0.5 flex items-center justify-end gap-2">
      <Button.button
        type="button"
        variant="ghost"
        class="@max-[27.5rem]:px-2 @max-[27.5rem]:text-sm pointer-coarse:min-block-11"
        phx-click="invoice_reject"
        phx-value-call={@id}
      >{gettext("Reject")}</Button.button>
      <Button.button
        type="button"
        variant="primary"
        accent="teal"
        class="@max-[27.5rem]:px-2.5 @max-[27.5rem]:text-sm pointer-coarse:min-block-11"
        phx-click="confirm_issuance"
        phx-value-call={@id}
        phx-disable-with={gettext("Issuing…")}
        disabled={not Issuance.confirmable?(@issuance)}
      >
        <Lucideicons.send class="size-4" aria-hidden="true" />{gettext("Confirm and send to KSeF")}
      </Button.button>
    </div>
    """
  end

  defp result(%{issuance: %{phase: :submitting}} = assigns) do
    ~H"""
    <p class="mbs-0.5 flex items-center gap-2 text-sm text-grey-600" role="status">
      <Lucideicons.loader_circle class="size-4 motion-safe:animate-spin" aria-hidden="true" />
      {Issuance.status_message(:submitting)}
    </p>
    """
  end

  defp result(%{issuance: %{phase: :submitted}} = assigns) do
    ~H"""
    <p class="mbs-0.5 flex items-start gap-2 text-sm text-grey-700" role="status">
      <Lucideicons.check class="mbs-0.5 size-4 flex-none text-moss-700" aria-hidden="true" />
      <span>
        {Issuance.status_message(:submitted)}
        <span class="block text-xs wrap-anywhere text-grey-600 tabular-nums">{@issuance.invoice.ksef_number}</span>
      </span>
    </p>
    """
  end

  defp result(assigns) do
    ~H"""
    <p class="mbs-0.5 flex items-start gap-2 text-sm text-brick-700" role="alert">
      <Lucideicons.triangle_alert class="mbs-0.5 size-4 flex-none" aria-hidden="true" />
      {Issuance.status_message(@issuance.phase)}
    </p>
    """
  end

  attr :id, :string, required: true
  attr :issuance, Issuance, required: true
  attr :class, :any, default: nil, doc: "Where the panel sits: beside the chat or over it."

  @doc "Renders the shared confirmation widget for the open invoice, beside or over the chat."
  @spec panel(map()) :: Rendered.t()
  def panel(assigns) do
    ~H"""
    <aside
      id="assistant-invoice-panel"
      class={["grid grid-rows-[auto_minmax(0,1fr)] bg-grey-50 min-block-0", @class]}
      aria-label={title(@issuance)}
    >
      <div class="flex items-center gap-1 ps-4 pe-2 min-block-13">
        <span class="flex-1 truncate font-medium text-grey-900">{title(@issuance)}</span>
        <Button.button
          type="button"
          variant="ghost"
          size="small"
          class="min-block-9 min-inline-9 pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
          phx-click="invoice_close"
          aria-label={gettext("Close the invoice preview")}
        >
          <Lucideicons.x class="size-5" aria-hidden="true" />
        </Button.button>
      </div>
      <div class="@container overflow-y-auto overscroll-contain px-4 pbs-1 pbe-8 md:px-6">
        <IssuanceWidget.issuance
          issuance={@issuance}
          footer_logo_url={~p"/images/invoice_firmowid_logo.png"}
          call={@id}
          stacked
        >
          <:actions>
            <Button.button
              type="button"
              variant="ghost"
              size="big"
              phx-click="invoice_reject"
              phx-value-call={@id}
            >{gettext("Reject")}</Button.button>
          </:actions>
        </IssuanceWidget.issuance>
      </div>
    </aside>
    """
  end

  defp title(%{kind: :correction} = issuance), do: gettext("Correction %{number}", number: number(issuance))

  defp title(issuance), do: gettext("VAT invoice %{number}", number: number(issuance))

  defp number(%{phase: :review} = issuance), do: issuance.invoice_number
  defp number(%{invoice: %{invoice_number: number}}), do: number
  defp number(_issuance), do: ""

  defp buyer(%{kind: :correction, invoice: invoice}) do
    gettext("to %{number} · %{buyer}",
      number: invoice.reference_invoice.invoice_number,
      buyer: invoice.buyer_full_name
    )
  end

  defp buyer(%{invoice: %{buyer_id: id} = invoice}) when id not in [nil, ""],
    do: gettext("%{buyer} · NIP %{tax_id}", buyer: invoice.buyer_full_name, tax_id: id)

  defp buyer(%{invoice: invoice}), do: invoice.buyer_full_name

  # An invoice lists its items; a correction only what it changes, paired by position as on the
  # document, with the change in gross value.
  defp items(%{kind: :correction, invoice: invoice}) do
    current = invoice.sales_invoice_items
    reference = invoice.reference_invoice.sales_invoice_items
    added = current |> Enum.drop(length(reference)) |> Enum.map(&{nil, &1})
    removed = reference |> Enum.drop(length(current)) |> Enum.map(&{&1, nil})

    (Enum.zip(reference, current) ++ added ++ removed)
    |> Enum.reject(fn {before, now} -> before && now && not item_changed?(before, now) end)
    |> Enum.map(&item_change(&1, invoice.currency))
  end

  defp items(%{invoice: invoice}), do: Enum.map(invoice.sales_invoice_items, &item_change({nil, &1}, invoice.currency))

  defp item_changed?(before, now) do
    before.name != now.name or before.unit != now.unit or
      not Decimal.eq?(before.quantity, now.quantity) or
      not Decimal.eq?(before.unit_price, now.unit_price) or
      not Decimal.eq?(before.gross_value, now.gross_value)
  end

  defp item_change({before, now}, currency) do
    shown = now || before

    %{
      name: shown.name,
      unit: shown.unit,
      quantity: changed(before, now, & &1.quantity, &Decimal.eq?/2),
      price: changed(before, now, &Money.new(currency, &1.unit_price), &Money.equal?/2),
      gross:
        Decimal.sub(
          if(now, do: now.gross_value, else: 0),
          if(before, do: before.gross_value, else: 0)
        )
    }
  end

  defp changed(nil, now, value, _equal?), do: value.(now)
  defp changed(before, nil, value, _equal?), do: value.(before)

  defp changed(before, now, value, equal?) do
    {old, new} = {value.(before), value.(now)}
    if equal?.(old, new), do: new, else: "#{old} → #{new}"
  end

  defp total_label(%{kind: :correction}), do: gettext("To pay after the correction")
  defp total_label(_issuance), do: gettext("Total to pay")

  defp total_details(%{kind: :correction, invoice: invoice}) do
    gettext("%{difference} against %{number}",
      difference:
        Money.new(
          invoice.currency,
          Decimal.sub(invoice.gross_value, invoice.reference_invoice.gross_value)
        ),
      number: invoice.reference_invoice.invoice_number
    )
  end

  defp total_details(%{invoice: invoice}) do
    gettext("net %{net} · VAT %{vat}",
      net: Money.new(invoice.currency, invoice.net_value),
      vat: Money.new(invoice.currency, invoice.vat_value)
    )
  end

  defp dates(%{kind: :correction, invoice: invoice}) do
    [
      invoice.correction_reason not in [nil, ""] &&
        gettext("Reason: %{reason}", reason: invoice.correction_reason),
      gettext("issued %{date}", date: format_date(invoice.issue_date))
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp dates(%{invoice: invoice}) do
    [
      gettext("Sale %{date}", date: format_date(invoice.sale_date)),
      gettext("due %{date}", date: format_date(invoice.due_date)),
      invoice.invoice_note not in [nil, ""] &&
        gettext("notes “%{note}”", note: invoice.invoice_note)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp format_date(nil), do: "—"
  defp format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp rejected_label(%{kind: :correction}), do: gettext("You rejected this correction.")
  defp rejected_label(_issuance), do: gettext("You rejected this invoice.")
end
