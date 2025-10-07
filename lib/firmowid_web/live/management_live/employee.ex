defmodule FirmowidWeb.ManagementLive.Employee do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Firmowid.Timetracker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    employee = Accounts.get_user!(id)
    projects = Timetracker.list_user_projects(id)

    socket =
      socket
      |> assign(:employee_id, id)
      |> assign(:employee, employee)
      |> assign(:projects, projects)
      |> assign(:tab, "projekty")

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_params(_unsigned_params, _uri, socket) do
    {:noreply, socket}
  end

  def return_to_employees_list(assigns) do
    ~H"""
    <.link
      navigate={~p"/zarzadzanie/pracownicy"}
      class="inline-block group"
    >
      <.icon name="hero-arrow-long-left" />
      <span class="group-hover:border-black border-b-2 border-transparent transition-colors">
        Powrót do listy pracowników
      </span>
    </.link>
    """
  end

  attr :label, :string, required: true
  slot :inner_block

  def user_card_info(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="text-darkGrey text-sm">{@label}</div>
      <div class="flex gap-2 items-center">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <div class={["text-black bg-white p-6 rounded-md shadow space-y-6", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  def employee_projects_tab(assigns) do
    ~H"""
    <.card>
      projects tab
      <div>
        <pre><%= inspect(@projects, pretty: true) %></pre>
      </div>
    </.card>
    """
  end

  def employee_profile_tab(assigns) do
    ~H"""
    <.card>profile tab</.card>
    """
  end

  def employee_documents_tab(assigns) do
    ~H"""
    <.card>documents tab</.card>
    """
  end

  def employee_leaves_tab(assigns) do
    ~H"""
    <.card>leaves tab</.card>
    """
  end
end
