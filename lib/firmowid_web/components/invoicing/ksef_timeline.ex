defmodule FirmowidWeb.Components.Invoicing.KsefTimeline do
  @moduledoc """
  Function component for displaying KSeF timeline events.

  Renders a chronological list of KSeF-related events for an invoice,
  derived from existing invoice data without requiring separate event storage.
  """

  use FirmowidWeb, :html

  alias Firmowid.Ksef.Timeline

  attr :invoice, :map, required: true
  attr :invoice_type, :atom, required: true, values: [:sales, :cost]

  @doc """
  Renders the KSeF timeline for an invoice.

  The timeline shows all KSeF-related events in chronological order.
  For sales invoices: creation, KSeF confirmation, corrections issued.
  For cost invoices: KSeF download, corrections issued.
  """
  def ksef_timeline(assigns) do
    events =
      case assigns.invoice_type do
        :sales -> Timeline.for_sales_invoice(assigns.invoice)
        :cost -> Timeline.for_cost_invoice(assigns.invoice)
      end

    assigns = assign(assigns, :events, events)

    ~H"""
    <div class="flex flex-col gap-4">
      <div class="flex flex-row justify-between items-center">
        <h3 class="text-sm uppercase text-darkGrey">Historia dokumentu</h3>
        <button
          phx-click="hide_ksef_timeline"
          phx-target="#invoice-show"
          class="text-sm text-darkGrey hover:text-black transition-all flex items-center gap-1"
        >
          <.icon name="hero-chevron-left-mini" class="w-4 h-4" /> Wróć do podglądu
        </button>
      </div>

      <ol :if={@events != []} class="flex flex-col gap-4 py-4">
        <li :for={{event, idx} <- Enum.with_index(@events, 1)} class="flex flex-row gap-4">
          <span class="text-darkGrey w-6 text-right shrink-0">{idx}.</span>
          <div class="flex flex-col gap-1">
            <div class="flex flex-row gap-2 items-baseline">
              <span class="text-sm text-darkGrey">
                {format_datetime(event.occurred_at)}
              </span>
              <span class="font-medium">
                {event_label(event.event)}
              </span>
            </div>
            <.event_details event={event} invoice_type={@invoice_type} />
          </div>
        </li>
      </ol>

      <p :if={@events == []} class="text-darkGrey py-4">
        Brak historii KSeF dla tego dokumentu.
      </p>
    </div>
    """
  end

  attr :event, :map, required: true
  attr :invoice_type, :atom, required: true

  defp event_details(%{event: %{event: :created}} = assigns) do
    ~H"""
    <span class="text-sm text-darkGrey">
      {@event.metadata.invoice_number}
    </span>
    """
  end

  defp event_details(%{event: %{event: :confirmed}} = assigns) do
    ~H"""
    <span class="text-sm text-darkGrey">
      {@event.metadata.ksef_number}
    </span>
    """
  end

  defp event_details(%{event: %{event: :downloaded}} = assigns) do
    ~H"""
    <span class="text-sm text-darkGrey">
      {@event.metadata.ksef_number}
    </span>
    """
  end

  defp event_details(%{event: %{event: :correction_issued}, invoice_type: :sales} = assigns) do
    ~H"""
    <.link
      navigate={invoice_path(@event.metadata.invoice_id, :sales)}
      class="text-sm text-blueText hover:underline"
    >
      {@event.metadata.invoice_number}
    </.link>
    """
  end

  defp event_details(%{event: %{event: :correction_issued}, invoice_type: :cost} = assigns) do
    ~H"""
    <.link
      navigate={invoice_path(@event.metadata.invoice_id, :cost)}
      class="text-sm text-blueText hover:underline"
    >
      {@event.metadata.invoice_identifier}
    </.link>
    """
  end

  defp event_details(assigns) do
    ~H"""
    """
  end

  defp event_label(:created), do: "Utworzenie dokumentu"
  defp event_label(:confirmed), do: "Wysłano i potwierdzono przez KSeF"
  defp event_label(:downloaded), do: "Pobrano z KSeF"
  defp event_label(:correction_issued), do: "Wystawienie faktury korygującej"

  defp format_datetime(nil), do: ""

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d.%m.%Y")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%d.%m.%Y")
  end

  defp invoice_path(invoice_id, :sales), do: ~p"/sprzedazowe/#{invoice_id}"
  defp invoice_path(invoice_id, :cost), do: ~p"/kosztowe/#{invoice_id}"
end
