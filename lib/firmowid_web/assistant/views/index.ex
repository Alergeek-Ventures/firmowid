defmodule FirmowidWeb.Assistant.Views.Index do
  @moduledoc """
  The full-screen assistant: the same assistant LiveView as the floating panel,
  rendered as a page with the conversation list. The layout leaves the panel
  out here, so the tab has a single chat.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Link
  import FirmowidWeb.Billing.Components.PlanNotice, only: [plan_notice: 1]
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Assistant.Utilities.Navigation
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
    <%= if Navigation.available?(@current_org) do %>
      {live_render(@socket, Floating,
        id: "assistant-page",
        container: {:div, class: "flex flex-1 flex-col"},
        session: %{"organization_id" => @current_org.id, "page" => true}
      )}
    <% else %>
      <div class="flex w-full flex-col gap-6 px-4 py-6 md:px-10 md:pt-8 md:pb-12">
        <h1 class="text-3xl/[1.3] font-bold text-grey-900">{@page_title}</h1>
        <.plan_notice feature={:assistant} current_org={@current_org} current_user={@current_user} />
        <.mcp_offer />
      </div>
    <% end %>
    """
  end

  # The assistant is paid, but the same tools work in Claude and ChatGPT on every plan.
  defp mcp_offer(assigns) do
    ~H"""
    <.alert title={gettext("Claude and ChatGPT work in every plan")}>
      {gettext(
        "Connect the MCP server to prepare invoices, match transfers and track time with AI, without the assistant."
      )}
      <:actions>
        <.link
          kind="unstyled"
          navigate={~p"/funkcje/claude-chatgpt-mcp"}
          class="font-semibold underline underline-offset-4"
        >
          {gettext("See how to connect")}
        </.link>
      </:actions>
    </.alert>
    """
  end
end
