defmodule FirmowidWeb.Landing.Views.Index do
  @moduledoc """
  Landing page for Firmowid marketing site.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.Landing

  alias FirmowidWeb.Infrastructure.UserAuth

  def mount(_params, _session, socket) do
    # Redirect authenticated users with organization to role-based landing.
    if socket.assigns[:current_user] && socket.assigns.current_user.organization_id do
      {:ok, push_navigate(socket, to: UserAuth.signed_in_path_for_user(socket.assigns.current_user))}
    else
      {:ok, socket, layout: false}
    end
  end
end
