defmodule FirmowidWeb.Management.Components.HoursRecordStatus do
  @moduledoc """
  Shared component for rendering an hours record status badge with optional download link.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Management.Utilities.Navigation

  attr :hours_record, :map, required: true
  attr :user, :map, required: true
  attr :show_change_request, :boolean, default: true

  def hours_record_status(%{hours_record: nil} = assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 items-center gap-3">
      <span class="bg-grey-200 text-caps-sm/tight text-grey-700 flex w-[166.5px] min-w-0 items-center justify-between gap-2.5 rounded-sm px-2 py-1 font-medium uppercase">
        Brak <.icon name="hero-x-mark-micro" class="size-4" />
      </span>
      <Lucideicons.file_x class="text-grey-400 shrink-0" />
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
            "text-caps-sm/tight flex w-[166.5px] min-w-0 items-center justify-between gap-2.5 rounded-sm px-2 py-1 font-medium uppercase",
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
          download={"Ewidencja_#{@hours_record.year}_#{@hours_record.month}_#{@user.name || @user.email}.pdf"}
          class="hover:bg-greyButtonBg inline-flex shrink-0 items-center justify-center rounded-md p-0.5 transition"
        >
          <.icon name="hero-arrow-down-tray-mini" class="text-grey-400 shrink-0" />
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
