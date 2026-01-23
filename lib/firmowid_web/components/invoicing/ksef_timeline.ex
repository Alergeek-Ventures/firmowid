defmodule FirmowidWeb.Components.Invoicing.KsefTimeline do
  @moduledoc """
  Function component for displaying KSeF timeline events.

  Renders a chronological list of KSeF-related events for an invoice,
  derived from existing invoice data and submission info.
  """

  use FirmowidWeb, :html

  alias Firmowid.Ksef.SubmissionInfo
  alias Firmowid.Ksef.Timeline

  attr :invoice, :map, required: true
  attr :invoice_type, :atom, required: true, values: [:sales, :cost]
  attr :submission_info, SubmissionInfo, default: nil

  @doc """
  Renders the KSeF timeline for an invoice.

  The timeline shows all KSeF-related events in chronological order.
  For sales invoices: creation, submission, confirmation/failure, corrections issued.
  For cost invoices: KSeF download, corrections issued.

  When `submission_info` is provided for sales invoices, it includes submission
  status events (submitted, confirmed, failed).
  """
  def ksef_timeline(assigns) do
    case_result =
      case assigns.invoice_type do
        :sales ->
          submission_info = assigns.submission_info || %SubmissionInfo{status: :not_submitted}
          Timeline.for_sales_invoice(assigns.invoice, submission_info)

        :cost ->
          Timeline.for_cost_invoice(assigns.invoice)
      end

    events = Enum.reverse(case_result)

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

      <div :if={@events != []} class="relative py-4">
        <div class="absolute left-[5px] top-[calc(1rem+5px)] bottom-[calc(1rem+5px)] w-0.5 bg-grey-200">
        </div>

        <div class="flex flex-col gap-6">
          <div :for={event <- @events} class="relative flex flex-row gap-4 items-start">
            <div class={[
              "relative z-10 w-3 h-3 rounded-full shrink-0 mt-1",
              event_dot_color(event.event)
            ]}>
            </div>

            <div class="flex flex-col gap-1">
              <div class="flex flex-row gap-2 items-baseline">
                <span class={[
                  "text-sm uppercase font-bold",
                  event.event == :failed && "text-redText"
                ]}>
                  {event_label(event.event)}
                </span>
                <span class="text-sm text-darkGrey">
                  {format_datetime(event.occurred_at)}
                </span>
              </div>
              <span class="text-sm text-darkGrey">
                <.event_details event={event} invoice_type={@invoice_type} />
              </span>
            </div>
          </div>
        </div>
      </div>

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
      nadano numer fakturze: {@event.metadata.invoice_number}
    </span>
    """
  end

  defp event_details(%{event: %{event: :submitted}} = assigns) do
    ~H"""
    <%= if @event.metadata.session_reference do %>
      nadano numer KSeF: {@event.metadata.session_reference}
    <% end %>
    """
  end

  defp event_details(%{event: %{event: :confirmed}} = assigns) do
    ~H"""
    {@event.metadata.ksef_number}
    """
  end

  defp event_details(%{event: %{event: :failed}} = assigns) do
    ~H"""
    <span>
      Zespół odpowiedzialny za integrację z KSeF został
      powiadomiony.
    </span>
    <span>
      Wysyłanie dokumentu zostanie automatycznie ponowione
      w ciągu 24 godzin.
    </span>
    """
  end

  defp event_details(%{event: %{event: :downloaded}} = assigns) do
    ~H"""
    <%= if @event.metadata.ksef_number do %>
      {@event.metadata.ksef_number}
    <% end %>
    """
  end

  defp event_details(%{event: %{event: :correction_issued}, invoice_type: :sales} = assigns) do
    ~H"""
    <.link
      navigate={invoice_path(@event.metadata.invoice_id, :sales)}
      class="text-sm text-blueText hover:underline"
    >
      wystawiono koretkę nr {@event.metadata.invoice_number}
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
  defp event_label(:submitted), do: "Wysłano do KSeF"
  defp event_label(:confirmed), do: "Potwierdzono przez KSeF"
  defp event_label(:failed), do: "Błąd wysyłki"
  defp event_label(:downloaded), do: "Pobrano z KSeF"
  defp event_label(:correction_issued), do: "Wystawienie faktury korygującej"

  defp event_dot_color(:confirmed), do: "bg-greenText"
  defp event_dot_color(:failed), do: "bg-redText"
  defp event_dot_color(:submitted), do: "bg-blueText"
  defp event_dot_color(:downloaded), do: "bg-greenText"
  defp event_dot_color(_), do: "bg-grey-200"

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
