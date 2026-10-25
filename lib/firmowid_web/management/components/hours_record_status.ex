defmodule FirmowidWeb.Management.Components.HoursRecordStatus do
  @moduledoc """
  Shared component for rendering an hours record status badge with optional download link.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Management.Utilities.Navigation

  attr :hours_record, :map, required: true
  attr :user, :map, required: true
  attr :show_change_request, :boolean, default: true

  def hours_record_status(%{hours_record: nil} = assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 items-center gap-3">
      <.badge class="w-[166.5px] justify-between">
        Brak <.icon name="hero-x-mark-micro" class="size-4" />
      </.badge>
      <Lucideicons.file_x class="shrink-0 text-grey-400" />
    </div>
    """
  end

  def hours_record_status(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 flex-col gap-2">
      <div class="flex items-center gap-3">
        <.badge
          tone={hours_record_tone(@hours_record.submission_status)}
          title={
            if @hours_record.submission_status == :withdrawn do
              gettext("Document submitted on %{date}",
                date: Calendar.strftime(@hours_record.inserted_at, "%d.%m.%Y %H:%M")
              )
            end
          }
          class="w-[166.5px] justify-between"
        >
          <%= if @hours_record.submission_status == :withdrawn do %>
            {gettext("Withdrawn")} <.icon name="hero-x-mark-micro" />
          <% else %>
            EWIDENCJA <.icon name="hero-check-micro" />
          <% end %>
        </.badge>
        <.link
          kind="unstyled"
          navigate={~p"/czasosledz/ewidencja/#{@hours_record.id}"}
          download={"Ewidencja_#{@hours_record.year}_#{@hours_record.month}_#{@user.member.name || @user.email}.pdf"}
          class="inline-flex shrink-0 items-center justify-center rounded-md p-0.5 transition hover:bg-grey-200"
        >
          <.icon name="hero-arrow-down-tray-mini" class="shrink-0 text-grey-400" />
        </.link>
      </div>
      <.link
        :if={@show_change_request && @hours_record.change_requested_at}
        kind="text"
        navigate={
          Navigation.employee_path(@user.id, %{
            miesiac: Date.new!(@hours_record.year, @hours_record.month, 1)
          })
        }
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

  defp hours_record_tone(:withdrawn), do: "neutral"
  defp hours_record_tone(_submitted), do: "success"
end
