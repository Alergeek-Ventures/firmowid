defmodule FirmowidWeb.ManagementLive.Employees do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Timetracker

  defp list_employees(filter_date, archived? \\ false, search \\ "") do
    import Ecto.Query, only: [from: 2]

    alias Firmowid.Accounts.User
    alias Firmowid.Repo

    query =
      from u in User,
        where: ^archived? == false,
        order_by: u.name

    query =
      if search == "" do
        query
      else
        from u in query,
          where: ilike(u.name, ^"%#{search}%") or ilike(u.email, ^"%#{search}%")
      end

    users = Repo.all(query)

    Enum.map(users, fn user ->
      hours = Timetracker.get_sessions_duration_in_month(user.id, filter_date)
      salary = Timetracker.get_latest_user_salary(user.id)

      user
      |> Map.put(:hours, hours)
      |> Map.put(:salary, salary)
    end)
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:employees, list_employees(Date.utc_today()))
      |> assign(:search, "")
      |> assign(:filter_date, Date.utc_today())
      |> assign(:archived?, false)
      |> assign(:wages_view?, false)
      |> assign(:search_expanded, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_archived_filter", %{"archived" => archived}, socket) do
    new_archived = archived == "true"

    {:noreply,
     socket
     |> assign(:archived?, new_archived)
     |> assign(:employees, list_employees(socket.assigns.filter_date, new_archived, socket.assigns.search))}
  end

  def handle_event("toggle_wages_view", _params, socket) do
    {:noreply, update(socket, :wages_view?, &(!&1))}
  end

  def handle_event("search", %{"q" => query}, socket) do
    socket =
      socket
      |> assign(:search, query)
      |> assign(:employees, list_employees(socket.assigns.filter_date, socket.assigns.archived?, query))

    {:noreply, socket}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply,
     socket
     |> assign(:filter_date, month)
     |> assign(:employees, list_employees(Date.from_iso8601!(month)))}
  end

  def handle_event("toggle_search", _params, socket) do
    {:noreply, update(socket, :search_expanded, &(!&1))}
  end

  def handle_event("employee_bank_number_copied", _params, socket) do
    {:noreply, put_flash(socket, :info, "Numer konta bankowego skopiowany do schowka")}
  end

  def handle_event("create_employee", _params, socket) do
    # TODO: implement creating employee
    {:noreply, socket}
  end
end
