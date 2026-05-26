defmodule FirmowidWeb.Invoicing.Components.InvoiceTimeline do
  @moduledoc """
  Renders a vertical timeline of events for an invoice (creation, KSeF
  submission, corrections, etc.). Used by both sales and cost invoice
  detail views.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]

  alias Firmowid.Ash.Invoicing.Services.Timeline
  alias Firmowid.Ash.Ksef.SubmissionInfo

  attr :invoice, :map, required: true
  attr :invoice_type, :atom, required: true, values: [:sales, :cost]
  attr :submission_info, SubmissionInfo, default: nil

  def invoice_timeline(assigns) do
    events =
      case assigns.invoice_type do
        :sales ->
          submission_info = assigns.submission_info || %SubmissionInfo{status: :not_submitted}
          Timeline.for_sales_invoice(assigns.invoice, submission_info)

        :cost ->
          Timeline.for_cost_invoice(assigns.invoice)
      end

    assigns = assign(assigns, :events, Enum.reverse(events))

    ~H"""
    <div class="flex flex-col gap-6">
      <div class="flex flex-row items-start justify-between">
        <h3 class="text-grey-700 text-sm/snug">Historia dokumentu</h3>
        <.button
          phx-click="hide_timeline"
          phx-target="#invoice-show"
          variant="secondary"
          size="small"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" /> Wróć do podglądu
        </.button>
      </div>

      <%= if Enum.empty?(@events) do %>
        <p class="text-grey-700 py-4">
          Brak historii dla tego dokumentu.
        </p>
      <% else %>
        <div class="relative">
          <div class="bg-grey-200 absolute top-4 bottom-7 left-[5px] w-0.5"></div>

          <div class="flex flex-col gap-6">
            <.event :for={event <- @events} event={event} invoice_type={@invoice_type} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :event, :map, required: true

  slot :label, required: true
  slot :content, required: false

  defp timeline_item(assigns) do
    ~H"""
    <div class="relative flex flex-row items-start gap-4">
      <div class={[
        "relative z-10 mt-1 size-3 shrink-0 rounded-full",
        event_dot_styles(@event.event)
      ]}>
      </div>

      <div class="flex flex-col gap-1">
        <div class="flex flex-row items-baseline gap-2">
          <span class={[
            "text-sm/snug font-bold uppercase",
            @event.event in [:failed, :correction_failed] && "text-redText"
          ]}>
            {render_slot(@label)}
          </span>
          <span class="text-grey-700 text-sm/snug">
            {format_datetime(@event.occurred_at)}
          </span>
        </div>
        <span class="text-grey-700 text-sm/snug">
          {render_slot(@content)}
        </span>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true
  attr :invoice_type, :atom, required: true

  defp event(%{event: %{event: :created}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Utworzenie dokumentu
      </:label>
      <:content>
        numer dokumentu:
        <span class="text-turquoise-700 font-bold">{@event.metadata.invoice_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :submitted}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Wysłano do KSeF
      </:label>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :confirmed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Potwierdzono przez KSeF
      </:label>
      <:content>
        nadano numer KSeF:
        <span class="text-turquoise-700 font-bold">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Błąd wysyłki
      </:label>
      <:content>
        Zespół odpowiedzialny za integrację z KSeF został powiadomiony.
        Wysyłanie dokumentu zostanie automatycznie ponowione w ciągu 24 godzin.
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :email_sent}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Faktura wysłana e-mailem
      </:label>
      <:content>
        Do kontrahenta wysłano wiadomość e-mail z fakturą.
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :email_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Błąd wysyłki e-maila
      </:label>
      <:content>
        <span>{@event.metadata.error_message || "Nie udało się wysłać wiadomości email"}</span>
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :reminder_sent}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Wysłano przypomnienie o płatności
      </:label>
      <:content>
        Do kontrahenta wysłano wiadomość e-mail z przypomnieniem o opłaceniu zaległej faktury.
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :reminder_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Błąd wysyłki przypomnienia
      </:label>
      <:content>
        <span>{@event.metadata.error_message || "Nie udało się wysłać wiadomości email"}</span>
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_email_sent}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Wysłano e-mail z korektą faktury
      </:label>
      <:content>
        Do kontrahenta wysłano wiadomość e-mail z fakturą korygującą.
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_email_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Błąd wysyłki e-maila z korektą faktury
      </:label>
      <:content>
        <span>{@event.metadata.error_message || "Nie udało się wysłać wiadomości email"}</span>
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :downloaded}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Pobrano z KSeF
      </:label>
      <:content>
        nadano numer KSeF:
        <span class="text-turquoise-700 font-bold">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_downloaded}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Pobrano fakturę korygującą {@event.metadata.invoice_identifier} z KSeF
      </:label>
      <:content>
        nadano numer KSeF:
        <span class="text-turquoise-700 font-bold">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_issued}, invoice_type: :sales} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Utworzenie faktury korygującej
      </:label>
      <:content>
        numer dokumentu:
        <span class="text-turquoise-700 font-bold">{@event.metadata.invoice_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_issued}, invoice_type: :cost} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Wystawienie faktury korygującej
      </:label>
      <:content>
        {@event.metadata.invoice_identifier}
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_submitted}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Wysłano korektę do KSeF
      </:label>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_confirmed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Korekta potwierdzona przez KSeF
      </:label>
      <:content>
        nadano numer KSeF:
        <span class="text-turquoise-700 font-bold">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        Błąd wysyłki korekty
      </:label>
      <:content>
        Zespół odpowiedzialny za integrację z KSeF został powiadomiony.
        Wysyłanie dokumentu zostanie automatycznie ponowione w ciągu 24 godzin.
      </:content>
    </.timeline_item>
    """
  end

  defp event(assigns) do
    ~H"""
    """
  end

  attr :email, :string, default: nil

  defp email_target(assigns) do
    ~H"""
    <%= if @email do %>
      <span>
        Adres docelowy: <span class="text-turquoise-700 font-bold">{@email}</span>
      </span>
    <% end %>
    """
  end

  defp event_dot_styles(:confirmed), do: "bg-greenText"
  defp event_dot_styles(:failed), do: "bg-redText"
  defp event_dot_styles(:submitted), do: "bg-blueText"
  defp event_dot_styles(:downloaded), do: "bg-greenText"
  defp event_dot_styles(:correction_downloaded), do: "bg-greenText"
  defp event_dot_styles(:correction_confirmed), do: "bg-greenText"
  defp event_dot_styles(:correction_failed), do: "bg-redText"
  defp event_dot_styles(:correction_submitted), do: "bg-blueText"
  defp event_dot_styles(:email_sent), do: "bg-blueText"
  defp event_dot_styles(:email_failed), do: "bg-redText"
  defp event_dot_styles(:reminder_sent), do: "bg-blueText"
  defp event_dot_styles(:reminder_failed), do: "bg-redText"
  defp event_dot_styles(:correction_email_sent), do: "bg-blueText"
  defp event_dot_styles(:correction_email_failed), do: "bg-redText"
  defp event_dot_styles(_), do: "bg-grey-200"

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
end
