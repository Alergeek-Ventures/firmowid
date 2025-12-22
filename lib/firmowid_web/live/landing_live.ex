defmodule FirmowidWeb.LandingLive do
  @moduledoc """
  Landing page for Firmowid marketing site.
  """
  use FirmowidWeb, :live_view

  def mount(_params, _session, socket) do
    # Redirect authenticated users with organization to timetracker
    if socket.assigns[:current_user] && socket.assigns.current_user.organization_id do
      {:ok, push_navigate(socket, to: ~p"/czasosledz")}
    else
      {:ok, socket, layout: false}
    end
  end
end
