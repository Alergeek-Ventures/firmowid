defmodule FirmowidWeb.HoursRecordLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.Timetracker

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:hours_record, Timetracker.get_hours_record!(id))}
  end

  defp page_title(:show), do: "Show Hours record"
  defp page_title(:edit), do: "Edit Hours record"
end
