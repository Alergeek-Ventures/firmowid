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
      <span class="flex w-[166.5px] min-w-0 items-center justify-between gap-2.5 rounded-sm bg-grey-200 px-2 py-1 text-caps-sm/tight font-medium text-grey-700 uppercase">
        Brak <.icon name="hero-x-mark-micro" class="size-4" />
      </span>
      <Lucideicons.file_x class="shrink-0 text-grey-400" />
    </div>
    """
  end

  def hours_record_status(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 flex-col gap-2">
      <div class="flex items-center gap-3">
        <span
          title={
            if @hours_record.submission_status == :withdrawn do
              gettext("Document submitted on %{date}",
                date: Calendar.strftime(@hours_record.inserted_at, "%d.%m.%Y %H:%M")
              )
            end
          }
          class={[
            "flex w-[166.5px] min-w-0 items-center justify-between gap-2.5 rounded-sm px-2 py-1 text-caps-sm/tight font-medium uppercase",
            if(@hours_record.submission_status == :withdrawn,
              do: "bg-orange-200 text-orange-700",
              else: "bg-green-200 text-green-700"
            )
          ]}
        >
          <%= if @hours_record.submission_status == :withdrawn do %>
            {gettext("Withdrawn")} <.icon name="hero-x-mark-micro" />
          <% else %>
            EWIDENCJA <.icon name="hero-check-micro" />
          <% end %>
        </span>
        <.link
          kind="unstyled"
          navigate={~p"/czasosledz/ewidencja/#{@hours_record.id}"}
          download={"Ewidencja_#{@hours_record.year}_#{@hours_record.month}_#{@user.member.name || @user.email}.pdf"}
          class="inline-flex shrink-0 items-center justify-center rounded-md p-0.5 transition hover:bg-greyButtonBg"
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
end
