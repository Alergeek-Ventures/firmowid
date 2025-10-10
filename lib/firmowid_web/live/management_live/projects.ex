defmodule FirmowidWeb.ManagementLive.Projects do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Management

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Management, :read_projects, socket.assigns.current_user)

    socket = assign(socket, :page_title, "Zarządzanie projektami")

    {:ok, socket}
  end
end
