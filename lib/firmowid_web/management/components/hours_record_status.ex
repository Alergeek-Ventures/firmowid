defmodule FirmowidWeb.Management.Components.HoursRecordStatus do
  @moduledoc """
  Shared component for rendering an hours record status badge with optional download link.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  attr :hours_record, :map, required: true
  attr :user, :map, required: true

  def hours_record_status(%{hours_record: nil} = assigns) do
    ~H"""
    <span class="bg-grey-200 text-caps-sm/tight text-grey-700 flex w-full min-w-[111px] items-center justify-between gap-2.5 rounded-sm px-2 py-1 font-medium uppercase">
      Brak <.icon name="hero-x-mark-micro" class="size-4" />
    </span>
    <Lucideicons.file_x class="text-grey-400 shrink-0" />
    """
  end

  def hours_record_status(assigns) do
    ~H"""
    <span class="text-caps-sm/tight flex w-full min-w-[111px] items-center justify-between gap-2.5 rounded-sm bg-green-200 px-2 py-1 font-medium text-green-700 uppercase">
      EWIDENCJA <.icon name="hero-check-micro" />
    </span>
    <.link
      kind="unstyled"
      navigate={~p"/czasosledz/ewidencja/#{@hours_record.id}"}
      download={"Ewidencja_#{@hours_record.year}_#{@hours_record.month}_#{@user.name || @user.email}.pdf"}
      class="hover:bg-greyButtonBg inline-flex items-center justify-center rounded-md p-0.5 transition"
    >
      <.icon name="hero-arrow-down-tray-mini" class="text-grey-400 shrink-0" />
    </.link>
    """
  end
end
