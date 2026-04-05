defmodule FirmowidWeb.Management.Views.Employees do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Session, as: AshSession

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    {:ok, active_months} = AshSession.months_with_sessions(%{}, scope: scope)

    socket =
      socket
      |> assign(:page_title, "Zarządzanie pracownikami")
      |> assign(:view, :standard)
      |> assign(:search_expanded, false)
      |> assign(:active_months, active_months)
      |> assign(:can_export_csv, socket.assigns.current_user.role == :admin)
      |> assign_form()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = Map.take(params, ["month", "q", "archived"])

    selected_date =
      case params do
        %{"month" => month} -> Date.from_iso8601!(month)
        _ -> Date.utc_today()
      end

    socket =
      socket
      |> assign(:params, params)
      |> assign(:selected_date, selected_date)
      |> assign(:search, params["q"] || "")
      |> assign(:archived, params["archived"] == "true")
      |> assign_employees()

    {:noreply, socket}
  end

  defp assign_employees(
         %{assigns: %{selected_date: selected_date, archived: archived, search: search, ash_scope: scope}} = socket
       ) do
    {:ok, employees} =
      AshSession.list_employees_for_month(
        selected_date,
        %{archived: archived, search: search},
        scope: scope
      )

    assign(socket, :employees, employees)
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(%{"wages_view" => socket.assigns.view != :standard}))
  end

  @impl true
  def handle_event("toggle_wages_view", _params, socket) do
    {:noreply,
     socket
     |> update(:view, fn
       :wages -> :standard
       :wage_editor -> :standard
       :standard -> :wages
     end)
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
    scope = socket.assigns.ash_scope

    entries =
      Enum.map(socket.assigns.employees, fn employee ->
        %{
          user_id: employee.user.id,
          hourly_rate: Decimal.new(employees_params[employee.user.id]["wage"])
        }
      end)

    case AshUserSalary.bulk_update_salaries(entries, scope: scope) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:view, :wages)
         |> push_event("unsaved-changed", %{value: false})
         |> assign_employees()}

      {:error, error} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Nie udało się zaktualizować stawek: #{inspect(error)}"
         )}
    end
  end

  def handle_event("search", %{"q" => search}, socket) do
    params = Map.put(socket.assigns.params, "q", search)
    {:noreply, push_patch(socket, to: ~p"/zarzadzanie/pracownicy?#{params}")}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    params = Map.put(socket.assigns.params, "month", month)
    {:noreply, push_patch(socket, to: ~p"/zarzadzanie/pracownicy?#{params}")}
  end

  def handle_event("toggle_search", _params, socket) do
    {:noreply, update(socket, :search_expanded, &(!&1))}
  end

  attr :hours_record, :map, required: true
  attr :user, :map, required: true

  def hours_record_status(%{hours_record: nil} = assigns) do
    ~H"""
    <span class="bg-grey-200 text-caps-sm/tight text-grey-700 flex w-[111px] items-center justify-between gap-2.5 rounded-sm px-2 py-1 font-medium uppercase">
      Brak <.icon name="hero-x-mark-micro" class="size-4" />
    </span>
    <Lucideicons.file_x class="text-grey-400 shrink-0" />
    """
  end

  def hours_record_status(assigns) do
    ~H"""
    <span class="text-caps-sm/tight flex w-full min-w-[111px] items-center justify-between gap-2.5 rounded-sm bg-green-200 px-2 py-1 font-medium text-green-700 uppercase">
      EWIDENCJA <.icon name="hero-check-micro" />
    </span>
    <a
      href={~p"/czasosledz/ewidencja/#{@hours_record.id}"}
      download={"Ewidencja_#{@hours_record.year}_#{@hours_record.month}_#{@user.name || @user.email}.pdf"}
      class="hover:bg-greyButtonBg inline-flex items-center justify-center rounded-md p-0.5 transition"
    >
      <.icon name="hero-arrow-down-tray-mini" class="text-grey-400 shrink-0" />
    </a>
    """
  end
end
