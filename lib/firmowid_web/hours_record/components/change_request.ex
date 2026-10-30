defmodule FirmowidWeb.HoursRecord.Components.ChangeRequest do
  @moduledoc "Shared presentation and organization-admin review controls for hours record change requests."
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidWeb.HoursRecord.Components.Status, only: [hours_record_status: 1]

  alias Phoenix.LiveView.Rendered

  @doc "Displays the request, its decision and optional administrator review controls."
  @spec change_request(map()) :: Rendered.t()
  attr :record, :map, required: true
  attr :reviewable, :boolean, default: false
  attr :target, :any, default: nil

  def change_request(assigns) do
    ~H"""
    <section
      id={"hours-record-change-#{@record.id}"}
      class="flex min-h-0 min-w-0 flex-1 flex-col gap-4"
    >
      <h3 class="shrink-0 text-base/tight font-medium text-grey-900">
        {gettext("Withdrawal request")}
      </h3>
      <p class="shrink-0 text-sm/snug text-grey-700">
        {kind_label(@record.change_request_kind)}
        <span :if={@record.change_reviewed_at}>
          · {Calendar.strftime(@record.change_reviewed_at, "%d.%m.%Y %H:%M")}
        </span>
      </p>
      <p
        class="scrollbar-card min-h-0 flex-1 overflow-y-auto text-base/snug wrap-break-word whitespace-pre-line text-grey-900"
        phx-no-format
      >{@record.change_request_reason}</p>
      <p :if={@record.change_request_decision == :rejected} class="text-sm/snug text-grey-700">
        {gettext(
          "The request was rejected. The submitted document remains current and the month's hours stay locked."
        )}
      </p>
      <div
        :if={@reviewable && is_nil(@record.change_request_decision)}
        class="flex shrink-0 flex-col gap-3"
      >
        <.button
          id={"accept-hours-record-change-#{@record.id}"}
          type="button"
          size="small"
          class="w-full"
          phx-click="review-hours-record-change"
          phx-value-id={@record.id}
          phx-value-decision="accepted"
          phx-target={@target}
          phx-disable-with={gettext("Saving...")}
        >
          {gettext("Accept request")}
        </.button>
        <.button
          id={"reject-hours-record-change-#{@record.id}"}
          type="button"
          variant="outline"
          size="small"
          class="w-full"
          phx-click="review-hours-record-change"
          phx-value-id={@record.id}
          phx-value-decision="rejected"
          phx-target={@target}
          phx-disable-with={gettext("Saving...")}
        >
          {gettext("Reject request")}
        </.button>
      </div>
    </section>
    """
  end

  @doc "Provides download links to withdrawn submissions without removing their signed documents."
  @spec submission_history(map()) :: Rendered.t()
  attr :records, :list, required: true
  attr :user, :map, required: true

  def submission_history(assigns) do
    ~H"""
    <section
      :if={@records != []}
      id="hours-record-submission-history"
      class="flex min-w-0 flex-col gap-4"
    >
      <h3 class="font-medium">{gettext("Previous documents")}</h3>
      <.hours_record_status
        :for={record <- @records}
        hours_record={record}
        user={@user}
      />
    </section>
    """
  end

  defp kind_label(:correction), do: gettext("Correction")
  defp kind_label(:cancellation), do: gettext("Cancellation")
end
