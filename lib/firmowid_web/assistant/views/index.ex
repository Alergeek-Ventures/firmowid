defmodule FirmowidWeb.Assistant.Views.Index do
  @moduledoc """
  The full-screen assistant: the same assistant LiveView as the floating panel,
  rendered as a page with the conversation list. The layout leaves the panel
  out here, so the tab has a single chat.
  """
  use FirmowidWeb, :live_view

  alias FirmowidWeb.Assistant.Views.Floating

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user.member.role == :employee do
      {:ok, push_navigate(socket, to: ~p"/skrzynka")}
    else
      {:ok, assign(socket, page_title: gettext("Firmowid assistant"), no_padding: true)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    {live_render(@socket, Floating,
      id: "assistant-page",
      container: {:div, class: "flex flex-1 flex-col"},
      session: %{"organization_id" => @current_org.id, "page" => true}
    )}
    """
  end
end
