defmodule FirmowidWeb.Management.Views.Employees do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Session
  alias FirmowidWeb.Core.Endpoint
  alias Phoenix.Socket.Broadcast

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope
    active_months = months_with_sessions(%{}, scope)

    if connected?(socket) do
      Endpoint.subscribe("user:joined_org:#{scope.tenant}")
    end

    socket =
      socket
      |> assign(:page_title, "Zarządzanie pracownikami")
      |> assign(:view, :standard)
      |> assign(:active_months, active_months)
      |> assign(:can_export_csv, socket.assigns.current_user.role == :admin)
      |> assign_form()

    {:ok, socket}
  end

  @impl true
  def handle_info(%Broadcast{topic: "user:joined_org:" <> _tenant}, socket) do
    {:noreply, assign_employees(socket)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = Map.take(params, ["month", "q"])

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
      |> assign_employees()

    {:noreply, socket}
  end

  defp assign_employees(%{assigns: %{selected_date: date, search: search, ash_scope: scope}} = socket) do
    if socket.assigns.current_user.role == :admin do
      # 1. Users (with optional search filter)
      list_filters =
        case socket.assigns.live_action do
          :index -> %{status: :active}
          :archive -> %{status: :archived}
        end

      search_filters = if search in [nil, ""], do: %{}, else: %{search: search}
      input = Map.merge(list_filters, search_filters)

      users =
        input
        |> Core.list_users!(scope: scope)
        |> Ash.load!([avatar_blob: [:url]], scope: scope)

      # 2. Time worked per user this month
      sessions =
        Session
        |> Ash.Query.for_read(:list, %{month: date.month, year: date.year}, scope: scope)
        |> Ash.Query.load(:duration)
        |> Ash.read!(scope: scope)

      time_by_user =
        sessions
        |> Enum.group_by(& &1.user_id)
        |> Map.new(fn {uid, ss} -> {uid, ss |> Enum.map(& &1.duration) |> Enum.sum()} end)

      # 3. Salaries as of this month
      salaries = AshUserSalary.as_of!(date, scope: scope)
      salary_by_user = Map.new(salaries, &{&1.user_id, &1.hourly_rate})

      # 4. Hours records for this month
      hours_records =
        Timetracker.list_hours_records!(%{month: date.month, year: date.year}, scope: scope)

      hr_by_user = Map.new(hours_records, &{&1.user_id, &1})

      # 5. Compose
      employees =
        users
        |> Enum.map(fn user ->
          %{
            user: user,
            time_worked: Map.get(time_by_user, user.id, 0),
            hourly_rate: Map.get(salary_by_user, user.id),
            hours_record: Map.get(hr_by_user, user.id)
          }
        end)
        |> Enum.sort_by(fn employee ->
          {
            employee.time_worked == 0,
            employee.user.name || employee.user.email ||
              ""
              |> to_string()
              |> String.downcase()
          }
        end)

      assign(socket, :employees, employees)
    else
      assign(socket, :employees, [])
    end
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

    path =
      case socket.assigns.live_action do
        :index -> ~p"/zarzadzanie/pracownicy?#{params}"
        :archive -> ~p"/zarzadzanie/pracownicy/archiwum?#{params}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    params = Map.put(socket.assigns.params, "month", month)

    path =
      case socket.assigns.live_action do
        :index -> ~p"/zarzadzanie/pracownicy?#{params}"
        :archive -> ~p"/zarzadzanie/pracownicy/archiwum?#{params}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("unarchive_employee", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    with {:ok, user} <- Core.get_org_user(%{id: id}, scope: scope, not_found_error?: false),
         {:ok, _user} <- Core.unarchive_user(user, %{}, scope: scope) do
      {:noreply, assign_employees(socket)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Nie udało się przywrócić pracownika")}
    end
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

  # Distinct months (as naive_datetime) that have sessions, newest first.
  defp months_with_sessions(filters, scope), do: Timetracker.months_with_sessions(filters, scope)
end
