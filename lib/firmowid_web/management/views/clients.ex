defmodule FirmowidWeb.Management.Views.Clients do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Management

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Management, :read_clients, socket.assigns.current_user)

    socket = assign(socket, :page_title, "Zarządzanie kontrahentami")

    {:ok, socket}
  end
end
