defmodule FirmowidWeb.HoursRecord.Components.Status do
  @moduledoc """
  Renders an hours record status badge with a download link and, when given a
  `change_request_path`, a link to the pending change request.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.Tooltip
  import Phoenix.Component, except: [link: 1]

  attr :hours_record, :map, required: true
  attr :user, :map, required: true
  attr :change_request_path, :string, default: nil

  def hours_record_status(%{hours_record: nil} = assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 items-center gap-3.75">
      <span class="flex h-6 w-27.75 min-w-0 items-center justify-between gap-2.5 rounded-sm bg-grey-200 px-2 text-caps-sm/tight font-medium text-grey-700 uppercase">
        {gettext("None")} <.figma_icon name="close" class="size-4" />
      </span>
      <.tooltip id={"timesheet-missing-#{@user.id}"} text={gettext("No timesheet for this month")}>
        <.figma_icon name="brak_pliku" class="size-6 text-grey-400" />
      </.tooltip>
    </div>
    """
  end

  def hours_record_status(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 flex-col gap-2">
      <div class="flex items-center gap-3.75">
        <span
          title={
            if @hours_record.submission_status == :withdrawn do
              gettext("Document submitted on %{date}",
                date: Calendar.strftime(@hours_record.inserted_at, "%d.%m.%Y %H:%M")
              )
            end
          }
          class={[
            "flex h-6 w-27.75 min-w-0 items-center justify-between gap-2.5 rounded-sm px-2 text-caps-sm/tight font-medium uppercase",
            if(@hours_record.submission_status == :withdrawn,
              do: "bg-rust-200 text-rust-700",
              else: "bg-moss-200 text-moss-700"
            )
          ]}
        >
          <%= if @hours_record.submission_status == :withdrawn do %>
            {gettext("Withdrawn")} <.icon name="hero-x-mark-micro" />
          <% else %>
            {pgettext("hours record badge", "Record")} <.icon name="hero-check-micro" />
          <% end %>
        </span>
        <.tooltip id={"timesheet-download-#{@user.id}"} text={gettext("Download timesheet")}>
          <.link
            kind="unstyled"
            navigate={~p"/czasosledz/ewidencja/#{@hours_record.id}"}
            download={"Ewidencja_#{@hours_record.year}_#{@hours_record.month}_#{@user.member.name || @user.email}.pdf"}
            class="inline-flex shrink-0 cursor-pointer items-center justify-center p-0.5 text-grey-700 transition-colors hover:text-black"
            aria-label={gettext("Download timesheet")}
          >
            <.icon name="hero-arrow-down-tray-mini" class="shrink-0" />
          </.link>
        </.tooltip>
      </div>
      <.link
        :if={@change_request_path && @hours_record.change_requested_at}
        kind="text"
        navigate={@change_request_path}
        class="text-sm wrap-break-word"
        title={@hours_record.change_request_reason}
      >
        <%= if @hours_record.change_request_decision == :rejected do %>
          {gettext("Change request rejected")}
        <% else %>
          {gettext("Change requested")}
        <% end %>
      </.link>
    </div>
    """
  end
end
