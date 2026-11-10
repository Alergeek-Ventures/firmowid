defmodule FirmowidMcp.Invoicing.Views.Issue do
  @moduledoc "User-confirmed invoice and correction issuance, with the existing asynchronous KSeF lifecycle."
  use FirmowidMcp, :live_view

  import FirmowidUI.Components.Button
  import Phoenix.Component

  alias Firmowid.Ksef
  alias FirmowidMcp.Invoicing, as: McpInvoicing
  alias FirmowidMcp.Invoicing.IssueCorrection
  alias FirmowidMcp.LiveSession
  alias FirmowidMcp.Widgets
  alias FirmowidUI.Invoicing.Components.Issuance, as: IssuanceWidget
  alias FirmowidUI.Invoicing.Issuance

  @impl true
  def mount(_params, session, socket) do
    widget = Widgets.for_resource(session["mcp_resource"])
    kind = if widget == IssueCorrection, do: :correction, else: :invoice

    socket =
      assign(socket,
        widget: widget,
        # Replaced with the signed tool input once the session is authorized.
        issuance: Issuance.new(kind, %{}, nil, McpInvoicing.action_context()),
        footer_logo_url: FirmowidMcp.endpoint().url() <> "/images/invoice_firmowid_logo.png"
      )

    LiveSession.mount(session, socket, widget,
      on_mount: &load_review/1,
      on_expire: &clear/1
    )
  end

  @impl true
  def handle_event(event, params, socket) do
    LiveSession.handle_event(event, params, socket, &handle_interaction/3)
  end

  defp handle_interaction("update_invoice_number", %{"invoice_number" => number}, socket) do
    {:noreply, update_issuance(socket, &Issuance.select_number(&1, number, socket.assigns.scope))}
  end

  defp handle_interaction("select_invoice_series", %{"number" => number}, socket) do
    {:noreply, update_issuance(socket, &Issuance.select_number(&1, number, socket.assigns.scope))}
  end

  defp handle_interaction("update_notes", %{"invoice_note" => note, "internal_note" => comment}, socket) do
    {:noreply, update_issuance(socket, &Issuance.update_notes(&1, note, comment))}
  end

  defp handle_interaction("confirm_issuance", _params, socket) do
    {:noreply, socket |> update_issuance(&Issuance.confirm(&1, socket.assigns.scope)) |> publish_context()}
  end

  defp handle_interaction("refresh_invoice_status", _params, socket) do
    {:noreply, socket |> update_issuance(&Issuance.refresh(&1, socket.assigns.scope)) |> publish_context()}
  end

  defp handle_interaction(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:ksef_invoice_status, status} = message, socket) do
    LiveSession.handle_info(message, socket, fn _message, socket ->
      {:noreply,
       socket
       |> update_issuance(&Issuance.ksef_status(&1, status, socket.assigns.scope))
       |> publish_context()}
    end)
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_review(socket) do
    %{kind: kind, context: context} = socket.assigns.issuance

    issuance =
      kind
      |> Issuance.new(socket.assigns.arguments, socket.assigns.confirmation_id, context)
      |> Issuance.load(socket.assigns.scope)

    if connected?(socket) and issuance.connection,
      do: Ksef.subscribe_ksef_status(socket.assigns.scope.tenant)

    socket |> assign(:issuance, issuance) |> publish_context()
  end

  defp update_issuance(socket, fun), do: assign(socket, :issuance, fun.(socket.assigns.issuance))

  defp publish_context(socket) do
    %{invoice: invoice, phase: phase, issued_id: issued_id} = socket.assigns.issuance

    push_event(socket, "mcp:context", %{
      structuredContent: %{
        state: phase,
        invoice_id: issued_id,
        invoice_number: if(invoice, do: invoice.invoice_number),
        ksef_number: if(invoice, do: invoice.ksef_number),
        requires_confirmation: phase == :review
      }
    })
  end

  defp clear(socket), do: assign(socket, :issuance, Issuance.clear(socket.assigns.issuance))

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="mcp-invoice-issuance"
      phx-hook="McpContext"
      class="@container p-2 min-inline-0"
      phx-disconnected={JS.set_attribute({"inert", ""})}
      phx-connected={JS.remove_attribute("inert")}
    >
      <IssuanceWidget.issuance
        issuance={@issuance}
        connected?={@connected?}
        available?={@status == :ready}
        footer_logo_url={@footer_logo_url}
      >
        <:notice>
          <p :if={@status == :expired} role="status" class="text-sm text-grey-600">
            {gettext("This view is unavailable.")}
          </p>
        </:notice>
        <:actions>
          <.button
            id="open-invoice-fullscreen"
            type="button"
            variant="outline"
            phx-hook="McpFullscreen"
            hidden
            aria-label={gettext("Preview the invoice in full screen")}
            data-tippy-content={gettext("Preview the invoice in full screen")}
            class="outline-offset-2 focus-visible:outline-2 active:opacity-80"
          >
            <Lucideicons.file_text class="size-4" aria-hidden="true" />
          </.button>
        </:actions>
      </IssuanceWidget.issuance>
    </section>
    """
  end
end
