defmodule FirmowidWeb.Assistant.Views.Index do
  @moduledoc """
  The full-screen assistant behind the `inbox` flag: the same assistant LiveView as the
  floating panel, rendered as a page with the conversation list. The layout leaves the panel
  out here, so the tab has a single chat.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias FirmowidWeb.Assistant.Views.Floating

  @impl true
  def mount(_params, _session, socket) do
    cond do
      not flag_enabled?(:inbox, socket.assigns) ->
        {:ok, push_navigate(socket, to: ~p"/fakturowanie")}

      socket.assigns.current_user.member.role == :employee ->
        {:ok, push_navigate(socket, to: ~p"/skrzynka")}

      true ->
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
