defmodule FirmowidWeb.Invoicing.Components.InvoiceTimeline do
  @moduledoc """
  Renders a vertical timeline of events for an invoice (creation, KSeF
  submission, corrections, etc.). Used by both sales and cost invoice
  detail views.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  alias Firmowid.Invoicing.Services.Timeline
  alias Firmowid.Ksef.SubmissionInfo

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
        <h3 class="text-sm/snug text-grey-700">{gettext("Document history")}</h3>
        <.button
          phx-click="hide_timeline"
          phx-target="#invoice-show"
          variant="secondary"
          size="small"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" /> {gettext("Back to preview")}
        </.button>
      </div>

      <%= if Enum.empty?(@events) do %>
        <p class="py-4 text-grey-700">
          {gettext("No history for this document.")}
        </p>
      <% else %>
        <div class="relative">
          <div class="absolute top-4 bottom-7 left-[5px] w-0.5 bg-grey-200"></div>

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
            @event.event in [:failed, :correction_failed] && "text-brick-700"
          ]}>
            {render_slot(@label)}
          </span>
          <span class="text-sm/snug text-grey-700">
            {format_datetime(@event.occurred_at)}
          </span>
        </div>
        <span class="text-sm/snug text-grey-700">
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
        {gettext("Document created")}
      </:label>
      <:content>
        {gettext("document number:")}
        <span class="font-bold text-teal-700">{@event.metadata.invoice_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :submitted}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Sent to KSeF")}
      </:label>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :confirmed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Confirmed by KSeF")}
      </:label>
      <:content>
        {gettext("KSeF number assigned:")}
        <span class="font-bold text-teal-700">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Submission error")}
      </:label>
      <:content>
        {gettext(
          "The team responsible for the KSeF integration has been notified. The document will be sent again automatically within 24 hours."
        )}
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :email_sent}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Invoice sent by email")}
      </:label>
      <:content>
        {gettext("An email with the invoice was sent to the counterparty.")}
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :email_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Email sending error")}
      </:label>
      <:content>
        <span>{@event.metadata.error_message || gettext("Failed to send the email message")}</span>
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :reminder_sent}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Payment reminder sent")}
      </:label>
      <:content>
        {gettext("An email reminding the counterparty to pay the overdue invoice was sent.")}
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :reminder_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Reminder sending error")}
      </:label>
      <:content>
        <span>{@event.metadata.error_message || gettext("Failed to send the email message")}</span>
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_email_sent}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Correction invoice email sent")}
      </:label>
      <:content>
        {gettext("An email with the correction invoice was sent to the counterparty.")}
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_email_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Correction invoice email sending error")}
      </:label>
      <:content>
        <span>{@event.metadata.error_message || gettext("Failed to send the email message")}</span>
        <.email_target email={@event.metadata.recipient_email} />
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :downloaded}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Downloaded from KSeF")}
      </:label>
      <:content>
        {gettext("KSeF number assigned:")}
        <span class="font-bold text-teal-700">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_downloaded}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Downloaded correction invoice %{number} from KSeF",
          number: @event.metadata.invoice_identifier
        )}
      </:label>
      <:content>
        {gettext("KSeF number assigned:")}
        <span class="font-bold text-teal-700">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_issued}, invoice_type: :sales} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Correction invoice created")}
      </:label>
      <:content>
        {gettext("document number:")}
        <span class="font-bold text-teal-700">{@event.metadata.invoice_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_issued}, invoice_type: :cost} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Correction invoice issued")}
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
        {gettext("Correction sent to KSeF")}
      </:label>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_confirmed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Correction confirmed by KSeF")}
      </:label>
      <:content>
        {gettext("KSeF number assigned:")}
        <span class="font-bold text-teal-700">{@event.metadata.ksef_number}</span>
      </:content>
    </.timeline_item>
    """
  end

  defp event(%{event: %{event: :correction_failed}} = assigns) do
    ~H"""
    <.timeline_item event={@event}>
      <:label>
        {gettext("Correction submission error")}
      </:label>
      <:content>
        {gettext(
          "The team responsible for the KSeF integration has been notified. The document will be sent again automatically within 24 hours."
        )}
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
        {gettext("Target address:")} <span class="font-bold text-teal-700">{@email}</span>
      </span>
    <% end %>
    """
  end

  defp event_dot_styles(:confirmed), do: "bg-moss-700"
  defp event_dot_styles(:failed), do: "bg-brick-700"
  defp event_dot_styles(:submitted), do: "bg-teal-800"
  defp event_dot_styles(:downloaded), do: "bg-moss-700"
  defp event_dot_styles(:correction_downloaded), do: "bg-moss-700"
  defp event_dot_styles(:correction_confirmed), do: "bg-moss-700"
  defp event_dot_styles(:correction_failed), do: "bg-brick-700"
  defp event_dot_styles(:correction_submitted), do: "bg-teal-800"
  defp event_dot_styles(:email_sent), do: "bg-teal-800"
  defp event_dot_styles(:email_failed), do: "bg-brick-700"
  defp event_dot_styles(:reminder_sent), do: "bg-teal-800"
  defp event_dot_styles(:reminder_failed), do: "bg-brick-700"
  defp event_dot_styles(:correction_email_sent), do: "bg-teal-800"
  defp event_dot_styles(:correction_email_failed), do: "bg-brick-700"
  defp event_dot_styles(_), do: "bg-grey-200"

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y")
end
