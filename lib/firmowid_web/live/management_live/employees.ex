defmodule FirmowidWeb.ManagementLive.Employees do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Management

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Management, :read_employees, socket.assigns.current_user)

    socket =
      socket
      |> assign(:filter_date, Date.utc_today())
      |> assign(:search, "")
      |> assign(:archived, false)
      |> assign(:view, :standard)
      |> assign(:search_expanded, false)
      |> assign_employees()
      |> assign_form()

    {:ok, socket}
  end

  defp assign_employees(socket) do
    assign(
      socket,
      :employees,
      Management.list_employees(socket.assigns.filter_date, socket.assigns.archived, socket.assigns.search)
    )
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(%{"wages_view" => socket.assigns.view != :standard}))
  end

  @impl true
  def handle_event("change_archived_filter", %{"archived" => archived}, socket) do
    {:noreply,
     socket
     |> assign(:archived, archived == "true")
     |> assign_employees()}
  end

  def handle_event("toggle_wages_view", _params, socket) do
    {:noreply,
     socket
     |> update(:view, &if(&1 == :wages, do: :standard, else: :wages))
     |> assign_form()}
  end

  def handle_event("toggle_wage_editor", _params, socket) do
    editing_wages = socket.assigns.view == :wages

    {:noreply,
     socket
     |> assign(:view, if(editing_wages, do: :wage_editor, else: :wages))
     |> push_event("unsaved-changed", %{value: editing_wages})}
  end

  def handle_event("save_wages", %{"employee" => employees_params}, %{assigns: %{view: :wage_editor}} = socket) do
    Bodyguard.permit!(Management, :change_user_wages, socket.assigns.current_user)

    case Management.update_user_salaries(socket.assigns.employees, employees_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:view, :wages)
         |> push_event("unsaved-changed", %{value: false})
         |> assign_employees()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Nie udało się zaktualizować stawek: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("search", %{"q" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign_employees()}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply,
     socket
     |> assign(:filter_date, Date.from_iso8601!(month))
     |> assign_employees()}
  end

  def handle_event("toggle_search", _params, socket) do
    {:noreply, update(socket, :search_expanded, &(!&1))}
  end

  def handle_event("employee_bank_number_copied", _params, socket) do
    {:noreply, put_flash(socket, :info, "Numer konta bankowego skopiowany do schowka")}
  end

  def handle_event("create_employee", _params, socket) do
    Bodyguard.permit!(Management, :create_employee, socket.assigns.current_user)
    # TODO: implement creating employee
    {:noreply, socket}
  end
end
