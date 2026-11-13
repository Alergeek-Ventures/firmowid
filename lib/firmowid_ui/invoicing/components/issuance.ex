defmodule FirmowidUI.Invoicing.Components.Issuance do
  @moduledoc """
  The invoice and correction confirmation widget shared by MCP and the assistant: the A4 preview,
  number and series, invoice note and comment, then sending and the KSeF result. It renders a
  `FirmowidUI.Invoicing.Issuance`; the caller's LiveView handles `update_invoice_number`,
  `select_invoice_series`, `update_notes`, `confirm_issuance` and `refresh_invoice_status`.
  """
  use FirmowidUI, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidUI.Invoicing.Components.InvoiceNotes
  alias FirmowidUI.Invoicing.Components.InvoiceNumber
  alias FirmowidUI.Invoicing.Components.SalesInvoice, as: InvoicePreview
  alias FirmowidUI.Invoicing.Issuance

  attr :issuance, Issuance, required: true
  attr :connected?, :boolean, default: true, doc: "False while the socket is not connected."

  attr :available?, :boolean,
    default: true,
    doc: "False once the interface's authorization expired."

  attr :footer_logo_url, :string, required: true

  attr :ksef_settings_url, :string,
    required: true,
    doc: "Absolute address of the web KSeF settings, opened in a new window when KSeF is not connected."

  attr :call, :string,
    default: nil,
    doc: "Sent as `call` with `confirm_issuance`, for a LiveView confirming several invoices."

  attr :stacked, :boolean,
    default: false,
    doc: """
    Shows the preview above the form at every width, scrolling sideways when narrower than A4.
    Otherwise the preview sits beside the form when there is room and is hidden when there is not.
    """

  slot :notice, doc: "Shown under the heading, such as an expired session."
  slot :actions, doc: "Placed before the confirm button."

  @doc "Renders the confirmation in its current phase."
  @spec issuance(map()) :: Phoenix.LiveView.Rendered.t()
  def issuance(assigns) do
    ~H"""
    <%!-- Inline, the heading, the notices and the form share one centred column of 37.5rem; --%>
    <%!-- with the preview beside the form, 67rem, so a wide frame does not stretch the form. --%>
    <div class={[
      "grid gap-4",
      !@stacked &&
        "@max-[58rem]:mx-auto @max-[58rem]:inline-full @max-[58rem]:max-inline-150 @min-[58rem]:max-inline-268"
    ]}>
      <div class="flex items-start justify-between gap-2">
        <h1 class={[
          "flex items-baseline gap-1 text-xl/tight font-medium",
          @issuance.phase not in [:review, :submitting, :submitted] && "text-brick-600"
        ]}>
          {Issuance.heading(@issuance)}
          <span :if={@issuance.phase == :submitting} class="inline-flex gap-1" aria-hidden="true">
            <span class="size-1.5 animate-bounce rounded-full bg-grey-400 [animation-delay:-0.3s]"></span>
            <span class="size-1.5 animate-bounce rounded-full bg-grey-400 [animation-delay:-0.15s]"></span>
            <span class="size-1.5 animate-bounce rounded-full bg-grey-400"></span>
          </span>
        </h1>
        <.button
          id="refresh-invoice-status"
          type="button"
          variant="outline"
          size="small"
          phx-click="refresh_invoice_status"
          phx-hook="Tippy"
          aria-label={gettext("Refresh")}
          data-tippy-content={gettext("Refresh")}
          class="outline-offset-2 focus-visible:outline-2 active:opacity-80"
        >
          <Lucideicons.refresh_cw class="size-4" aria-hidden="true" />
        </.button>
      </div>
      {render_slot(@notice)}
      <p :for={error <- @issuance.errors} role="alert" class="text-sm text-brick-600">{error}</p>
      <%= if @available? do %>
        <p
          :if={
            (@issuance.phase == :review and @issuance.connection) &&
              @issuance.connection.status != :connected
          }
          role="status"
          class="text-sm text-grey-600"
        >
          {gettext("Connect KSeF before issuing the invoice.")}
          <.link
            kind="unstyled"
            external={@ksef_settings_url}
            target="_blank"
            rel="noopener noreferrer"
            class="underline underline-offset-4"
          >
            {gettext("Open KSeF settings in Firmowid")}
          </.link>
        </p>
        <div class={[
          "grid items-start gap-6",
          !@stacked && "@min-[58rem]:grid-cols-[37.5rem_minmax(0,1fr)]"
        ]}>
          <%!-- The preview needs full width; narrower, as inline in the conversation, it is hidden. --%>
          <div
            :if={@issuance.invoice}
            id="invoice-preview"
            class={[
              "rounded-lg border border-grey-200 bg-white shadow-sm",
              if(@stacked,
                do: "justify-self-start overflow-x-auto max-inline-full",
                else: "overflow-clip @max-[58rem]:hidden @min-[58rem]:mbs-7"
              )
            ]}
            tabindex="0"
          >
            <%!-- mbs-7 is the number label's height, so the document starts level with the input. --%>
            <%!-- Stacked in a narrow column, the A4 document scales down to its width. --%>
            <div class={[@stacked && "@max-[38rem]:zoom-[.58] @max-[22rem]:zoom-[.47]"]}>
              <InvoicePreview.sales_invoice
                sales_invoice={Map.put(@issuance.invoice, :buyer_pesel, nil)}
                currency_rate={@issuance.currency_rate}
                show_vat={@issuance.show_vat}
                reference_invoice={@issuance.invoice.reference_invoice}
                footer_logo_data_uri={@footer_logo_url}
              />
            </div>
          </div>
          <%!-- As wide as the column inline, beside the preview in full screen. --%>
          <div
            :if={@issuance.invoice && @issuance.phase == :review}
            class={["grid gap-4 inline-full", @stacked && "max-inline-150"]}
          >
            <InvoiceNumber.invoice_number
              invoice_number={@issuance.invoice_number}
              next_numbers_by_series={@issuance.next_numbers_by_series}
              warnings={@issuance.invoice_warnings}
            />
            <InvoiceNotes.invoice_notes
              :if={@issuance.kind == :invoice}
              invoice_note={@issuance.invoice.invoice_note}
              internal_note={@issuance.invoice.internal_note}
              class={[
                "[&_label]:text-xs [&_textarea]:text-xs",
                if(@stacked,
                  do: "grid-cols-[repeat(auto-fit,minmax(min(100%,13.75rem),1fr))]",
                  else: "@max-[58rem]:grid-cols-2"
                )
              ]}
            />
            <div class="flex flex-wrap items-center justify-end gap-2">
              {render_slot(@actions)}
              <.button
                id="confirm-invoice-issuance"
                type="button"
                variant="primary"
                accent="teal"
                phx-click="confirm_issuance"
                phx-value-call={@call}
                phx-disable-with={gettext("Issuing…")}
                disabled={not @connected? or not Issuance.confirmable?(@issuance)}
                class="grow justify-center outline-offset-2 focus-visible:outline-2 active:opacity-80 disabled:opacity-50"
              >
                <Lucideicons.send class="size-4" aria-hidden="true" />
                {gettext("Confirm and send to KSeF")}
              </.button>
            </div>
          </div>
          <div
            :if={@issuance.phase in [:submitting, :submitted]}
            id="invoice-submission-status"
            role="status"
            aria-live="polite"
            class={[
              "grid justify-items-center gap-3 py-6 text-center",
              !@stacked && "@min-[58rem]:mbs-7"
            ]}
          >
            <Lucideicons.circle_check
              :if={@issuance.phase == :submitted}
              class="size-16 text-moss-700"
              aria-hidden="true"
            />
            <p class="text-sm text-grey-600">{Issuance.status_message(@issuance.phase)}</p>
            <p
              :if={@issuance.phase == :submitted and @issuance.invoice}
              class="text-sm font-medium wrap-break-word text-grey-700"
            >
              {@issuance.invoice.ksef_number}
            </p>
          </div>
          <div
            :if={@issuance.phase in [:failed, :not_submitted, :returned_to_draft, :deleted]}
            id="invoice-submission-status"
            role="alert"
            class={[
              "grid justify-items-center gap-3 rounded-md bg-brick-200 p-6 text-center text-brick-700",
              !@stacked && "@min-[58rem]:mbs-7"
            ]}
          >
            <Lucideicons.triangle_alert class="size-10 text-brick-600" aria-hidden="true" />
            <p class="text-sm">{Issuance.status_message(@issuance.phase)}</p>
            <p
              :if={
                (@issuance.phase == :failed and @issuance.submission_info) &&
                  @issuance.submission_info.error
              }
              class="text-sm"
            >
              {@issuance.submission_info.error}
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
