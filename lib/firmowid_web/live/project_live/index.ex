defmodule FirmowidWeb.Project.Index do
  alias Firmowid.Accounts
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias FirmowidWeb.Helpers.TimeFormatter
  alias Firmowid.Repo
  use FirmowidWeb, :live_view
  import FirmowidWeb.Components.Timetracker.SubnavigationButtons

  defmodule EmployeeSalaryForm do
    use Firmowid.Schema
    import Ecto.Changeset

    embedded_schema do
      field :hourly_rate, :string
      field :fixed_salary, :string
      field :salary_type, :string
    end

    def changeset(attrs \\ %{}) do
      changeset(%__MODULE__{}, attrs)
    end

    def changeset(salary, attrs) do
      salary
      |> cast(attrs, [:hourly_rate, :fixed_salary, :salary_type])
      |> calculate_hourly_rate()
    end

    defp calculate_hourly_rate(changeset) do
      salary_type = get_change(changeset, :salary_type) || get_field(changeset, :salary_type)

      case salary_type do
        "fixed" ->
          # Calculate hourly rate from fixed salary (fixed_salary / 168 hours per month)
          case get_change(changeset, :fixed_salary) || get_field(changeset, :fixed_salary) do
            nil ->
              changeset

            "" ->
              changeset

            fixed_salary_str ->
              case Float.parse(fixed_salary_str) do
                {fixed_salary, _} ->
                  hourly_rate = fixed_salary / 168
                  hourly_rate_rounded = Float.round(hourly_rate, 2)
                  hourly_rate_str = :erlang.float_to_binary(hourly_rate_rounded, decimals: 2)
                  put_change(changeset, :hourly_rate, hourly_rate_str)

                :error ->
                  changeset
              end
          end

        "hourly" ->
          # Calculate fixed salary from hourly rate (hourly_rate * 168 hours per month)
          case get_change(changeset, :hourly_rate) || get_field(changeset, :hourly_rate) do
            nil ->
              changeset

            "" ->
              changeset

            hourly_rate_str ->
              case Float.parse(hourly_rate_str) do
                {hourly_rate, _} ->
                  fixed_salary = hourly_rate * 168
                  fixed_salary_rounded = Float.round(fixed_salary, 2)
                  fixed_salary_str = :erlang.float_to_binary(fixed_salary_rounded, decimals: 2)
                  put_change(changeset, :fixed_salary, fixed_salary_str)

                :error ->
                  changeset
              end
          end

        _ ->
          changeset
      end
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Timetracker, :read_projects, socket.assigns.current_user)
    Bodyguard.permit!(Timetracker, :read_hours_records, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       projects: Timetracker.list_projects(),
       is_editing_name: false,
       is_editing_users: false,
       editing_employee_salaries: %{},
       employee_salary_forms: %{}
     )}
  end

  @impl true
  def handle_params(%{"id" => project_id} = params, _, socket) do
    {:noreply,
     socket
     |> assign(:selected_project, Enum.find(socket.assigns.projects, &(&1.id == project_id)))
     |> assign(:active_months, Timetracker.get_months_with_sessions_by_project(project_id))
     |> assign_selected_date(params)
     |> load_project_hours()}
  end

  def handle_params(params, _, socket) do
    {:noreply,
     socket
     |> assign(selected_project: nil)
     |> assign(active_months: Timetracker.get_months_with_sessions())
     |> assign_selected_date(params)
     |> assign_hours_records()}
  end

  def handle_event("edit_name", _, %{assigns: %{selected_project: project}} = socket) do
    changeset = project |> Project.form_changeset()

    {:noreply, assign(socket, form: to_form(changeset), is_editing_name: true)}
  end

  def handle_event("edit_users", _, %{assigns: %{selected_project: project}} = socket) do
    project = Repo.preload(project, project_users: :user)

    {:noreply,
     socket
     |> assign(is_editing_users: true)
     |> assign(selected_project: project)
     |> assign_project_users(
       project.project_users
       |> Enum.map(& &1.user)
       |> Enum.map(&Accounts.get_user_with_avatar/1)
     )}
  end

  def handle_event("edit_all_users", _, socket) do
    all_users =
      socket.assigns.hours_records
      |> Enum.map(& &1.user)
      |> Enum.map(fn user ->
        salary = Timetracker.get_latest_user_salary(user.id)
        Map.put(user, :current_salary, salary)
      end)

    {:noreply,
     socket
     |> assign(is_editing_users: true)
     |> assign(all_users: all_users)}
  end

  def handle_event("delete_user", %{"user_id" => user_id}, socket) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)

    project_users =
      socket.assigns.project_users
      |> Enum.reject(&(&1.id == user_id))

    {:noreply, assign_project_users(socket, project_users)}
  end

  def handle_event("add_user", %{"user_id" => user_id}, socket) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)

    project_users =
      socket.assigns.project_users ++
        [Enum.find(socket.assigns.users, &(&1.id == user_id))]

    {:noreply, assign_project_users(socket, project_users)}
  end

  def handle_event("save_users", _, socket) do
    if socket.assigns.selected_project do
      Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)
      project = socket.assigns.selected_project
      project_users = socket.assigns.project_users |> Enum.map(& &1.id)

      {:ok, project} = Timetracker.set_users_to_project(project, project_users)

      {:noreply,
       socket
       |> load_project_hours()
       |> assign(
         is_editing_users: false,
         selected_project: project,
         users: nil,
         project_users: nil
       )}
    else
      # IF editing users for all projects - just exit edit mode and refresh hours records
      {:noreply,
       socket
       |> assign(is_editing_users: false)
       |> assign_hours_records()}
    end
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, is_editing_name: false, is_editing_users: false, form: nil)}
  end

  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      socket.assigns.selected_project
      |> Project.form_changeset(params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"project" => params}, socket) do
    Bodyguard.permit!(Timetracker, :update_project, socket.assigns.current_user)
    project = socket.assigns.selected_project

    case Timetracker.update_project(project, params) do
      {:ok, project} ->
        {:noreply,
         assign(socket,
           is_editing_name: false,
           projects: Timetracker.list_projects(),
           selected_project: project
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("select_project", %{"_target" => ["reset"]}, socket) do
    params = %{"month" => Date.to_iso8601(socket.assigns.selected_date)}
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty?#{params}")}
  end

  def handle_event("select_project", %{"selected_project" => ""}, socket) do
    params = %{"month" => Date.to_iso8601(socket.assigns.selected_date)}
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty?#{params}")}
  end

  def handle_event("select_project", %{"selected_project" => project_id}, socket) do
    params = %{"month" => Date.to_iso8601(socket.assigns.selected_date)}
    {:noreply, push_patch(socket, to: ~p"/czasosledz/projekty/#{project_id}?#{params}")}
  end

  @impl true
  def handle_event("change-month", %{"month" => month_string}, socket) do
    params = %{"month" => month_string}
    project = socket.assigns.selected_project

    path =
      if project do
        ~p"/czasosledz/projekty/#{project.id}?#{params}"
      else
        ~p"/czasosledz/projekty?#{params}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("toggle-user", %{"id" => user_id}, socket) do
    user_hours =
      socket.assigns.project_user_hours
      |> Enum.map(fn
        %{id: ^user_id} = user ->
          user
          |> Map.put(:expanded, !user.expanded)
          |> Map.put_new_lazy(
            :sessions,
            fn ->
              Timetracker.get_grouped_user_project_sessions(
                user_id,
                socket.assigns.selected_project.id,
                socket.assigns.selected_date
              )
            end
          )

        user ->
          user
      end)

    {:noreply, assign(socket, :project_user_hours, user_hours)}
  end

  def handle_event("edit_employee_salary", %{"user_id" => user_id}, socket) do
    employee_salary_forms = socket.assigns.employee_salary_forms
    editing_employee_salaries = socket.assigns.editing_employee_salaries

    current_user =
      if socket.assigns.selected_project do
        Enum.find(socket.assigns.project_users, &(&1.id == user_id))
      else
        case Enum.find(socket.assigns.hours_records, fn record -> record.user.id == user_id end) do
          nil -> nil
          record -> record.user
        end
      end

    initial_values =
      case current_user && current_user.current_salary do
        nil ->
          %{"hourly_rate" => "", "fixed_salary" => "", "salary_type" => "hourly"}

        salary ->
          hourly_rate_str = Decimal.to_string(salary.hourly_rate)
          fixed_salary = Decimal.mult(salary.hourly_rate, Decimal.new("168"))
          fixed_salary_str = Decimal.to_string(fixed_salary)

          %{
            "hourly_rate" => hourly_rate_str,
            "fixed_salary" => fixed_salary_str,
            "salary_type" => "hourly"
          }
      end

    form =
      Map.get(employee_salary_forms, user_id) ||
        to_form(EmployeeSalaryForm.changeset(initial_values),
          as: "employee_salary_form_#{user_id}"
        )

    updated_forms = Map.put(employee_salary_forms, user_id, form)
    updated_editing = Map.put(editing_employee_salaries, user_id, true)

    {:noreply,
     assign(socket,
       employee_salary_forms: updated_forms,
       editing_employee_salaries: updated_editing
     )}
  end

  def handle_event("cancel_edit_employee_salary", %{"user_id" => user_id}, socket) do
    editing_employee_salaries = Map.put(socket.assigns.editing_employee_salaries, user_id, false)
    employee_salary_forms = Map.delete(socket.assigns.employee_salary_forms, user_id)

    {:noreply,
     assign(socket,
       editing_employee_salaries: editing_employee_salaries,
       employee_salary_forms: employee_salary_forms
     )}
  end

  def handle_event("validate_employee_salary", event_params, socket) do
    user_id = Map.get(event_params, "user_id")
    form_key = "employee_salary_form_#{user_id}"
    params = Map.get(event_params, form_key)

    require Logger

    if user_id && params do
      current_form = Map.get(socket.assigns.employee_salary_forms, user_id)

      current_values =
        if current_form do
          %{
            "hourly_rate" => current_form[:hourly_rate].value,
            "fixed_salary" => current_form[:fixed_salary].value,
            "salary_type" => current_form[:salary_type].value
          }
        else
          %{"hourly_rate" => "", "fixed_salary" => "", "salary_type" => "hourly"}
        end

      merged_params =
        if params["salary_type"] == "fixed" do
          Map.merge(current_values, params) |> Map.delete("hourly_rate")
        else
          Map.merge(current_values, params)
        end

      changeset = EmployeeSalaryForm.changeset(merged_params)

      updated_forms =
        Map.put(socket.assigns.employee_salary_forms, user_id, to_form(changeset, as: form_key))

      {:noreply, assign(socket, employee_salary_forms: updated_forms)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_employee_salary", event_params, socket) do
    Bodyguard.permit!(Timetracker, :create_user_salary, socket.assigns.current_user)
    user_id = Map.get(event_params, "user_id")
    form_key = "employee_salary_form_#{user_id}"
    params = Map.get(event_params, form_key)

    require Logger

    if user_id && params do
      salary_attrs = prepare_user_salary_attrs(params, user_id)
      Logger.info("Prepared salary attrs: #{inspect(salary_attrs)}")

      case Timetracker.create_user_salary(salary_attrs) do
        {:ok, user_salary} ->
          Logger.info("Successfully created user salary: #{inspect(user_salary)}")

          editing_employee_salaries =
            Map.put(socket.assigns.editing_employee_salaries, user_id, false)

          socket = assign_hours_records(socket)

          {:noreply,
           assign(socket,
             editing_employee_salaries: editing_employee_salaries
           )}

        {:error, create_changeset} ->
          Logger.info(
            "Create failed, attempting to update existing salary record: #{inspect(create_changeset.errors)}"
          )

          # error means there already exists salary record for this user that has been created on the same day
          # try to find and update most recent record for this user and date (today) instead of creating another one
          case Timetracker.get_latest_user_salary(user_id) do
            nil ->
              Logger.error(
                "No existing salary record found to update, create failed with: #{inspect(create_changeset.errors)}"
              )

              LiveToast.send_toast(:error, "Zmiana wynagrodzenia pracownika nie powiodła się")
              {:noreply, socket}

            existing_salary ->
              Logger.info("Found existing salary record: #{inspect(existing_salary)}")

              case Timetracker.update_user_salary(existing_salary, salary_attrs) do
                {:ok, updated_salary} ->
                  Logger.info("Successfully updated user salary: #{inspect(updated_salary)}")

                  editing_employee_salaries =
                    Map.put(socket.assigns.editing_employee_salaries, user_id, false)

                  socket = assign_hours_records(socket)

                  {:noreply,
                   assign(socket,
                     editing_employee_salaries: editing_employee_salaries
                   )}

                {:error, update_changeset} ->
                  Logger.error(
                    "Both create and update failed. Create errors: #{inspect(create_changeset.errors)}, Update errors: #{inspect(update_changeset.errors)}"
                  )

                  LiveToast.send_toast(:error, "Zmiana wynagrodzenia pracownika nie powiodła się")
                  {:noreply, socket}
              end
          end
      end
    else
      Logger.warning(
        "Missing user_id or params - user_id: #{inspect(user_id)}, params: #{inspect(params)}"
      )

      {:noreply, socket}
    end
  end

  def handle_event("toggle-user-summary", %{"id" => user_id}, socket) do
    hours_records =
      socket.assigns.hours_records
      |> Enum.map(fn
        %{id: ^user_id} = record ->
          Map.put(record, :expanded, !record.expanded)

        record ->
          record
      end)

    {:noreply, assign(socket, :hours_records, hours_records)}
  end

  defp format_hourly_rate(nil), do: "Brak stawki"

  defp format_hourly_rate(hourly_rate) do
    "#{Decimal.to_string(hourly_rate)} PLN/h"
  end

  defp get_current_hourly_rate(user) do
    case user.current_salary do
      nil -> nil
      salary -> salary.hourly_rate
    end
  end

  defp prepare_user_salary_attrs(params, user_id) do
    # Calculate hourly rate based on salary type
    hourly_rate =
      case params["salary_type"] do
        "fixed" ->
          # Convert fixed salary to hourly rate (fixed_salary / 168 hours per month)
          case params["fixed_salary"] do
            nil ->
              nil

            "" ->
              nil

            fixed_salary_str ->
              case Float.parse(fixed_salary_str) do
                {fixed_salary, _} ->
                  hourly_rate = Decimal.from_float(fixed_salary / 168)
                  Decimal.round(hourly_rate, 2)

                :error ->
                  nil
              end
          end

        "hourly" ->
          case params["hourly_rate"] do
            nil ->
              nil

            "" ->
              nil

            hourly_rate_str ->
              case Float.parse(hourly_rate_str) do
                {_hourly_rate, _} ->
                  hourly_rate = Decimal.new(hourly_rate_str)
                  Decimal.round(hourly_rate, 2)

                :error ->
                  nil
              end
          end

        _ ->
          nil
      end

    %{
      user_id: user_id,
      hourly_rate: hourly_rate,
      effective_from: Date.utc_today()
    }
  end

  defp assign_project_users(socket, project_users) do
    assign(socket,
      users:
        Timetracker.list_users_with_projects()
        |> Enum.map(&Accounts.get_user_with_avatar/1)
        |> Enum.reject(fn user ->
          Enum.any?(project_users, &(&1.id == user.id))
        end)
        |> Enum.sort_by(&{&1.name, &1.email}),
      project_users: project_users
    )
  end

  defp assign_selected_date(socket, params) do
    date =
      case Map.get(params, "month") do
        nil -> Date.utc_today()
        month -> Date.from_iso8601!(month)
      end

    assign(socket, selected_date: date)
  end

  defp assign_hours_records(socket) do
    date = socket.assigns.selected_date

    socket
    |> assign(
      total_time_worked: Timetracker.get_total_time_worked(date.month, date.year),
      most_demanding_project: Timetracker.get_most_demanding_project(date.month, date.year),
      hours_records:
        Timetracker.get_month_hours_records(date.month, date.year)
        |> Enum.map(&Map.put(&1, :id, &1.user.id))
        |> Enum.map(&Map.put(&1, :user, Accounts.get_user_with_avatar(&1.user)))
        |> Enum.map(&Map.put(&1, :expanded, false))
        |> Enum.map(fn record ->
          time_worked = Timetracker.get_sessions_duration_in_month(record.user.id, date)
          user_hours = %{time_worked: time_worked}
          current_salary = Timetracker.get_latest_user_salary(record.user.id)
          user_with_salary = Map.put(record.user, :current_salary, current_salary)

          record
          |> Map.put(:user_hours, user_hours)
          |> Map.put(:user, user_with_salary)
        end)
    )
  end

  defp load_project_hours(%{assigns: %{selected_project: nil}} = socket) do
    socket
    |> assign(:project_user_hours, [])
    |> assign(:total_time_worked, 0)
  end

  defp load_project_hours(socket) do
    date = socket.assigns.selected_date
    project_id = socket.assigns.selected_project.id

    project_user_hours =
      Timetracker.get_month_summary_by_project(project_id, date.month, date.year)
      |> Enum.map(fn %{user: u, time_worked: t, removed_from_project: r} ->
        Accounts.get_user_with_avatar(u)
        |> Map.put(:time_worked, t)
        |> Map.put(:removed_from_project, r)
        |> Map.put(:expanded, false)
      end)
      |> Enum.sort_by(&{&1.removed_from_project, &1.name, &1.email})

    total_project_seconds = Enum.sum_by(project_user_hours, & &1.time_worked)

    most_active_user =
      project_user_hours
      |> Enum.max_by(& &1.time_worked, fn -> nil end)

    socket
    |> assign(:project_user_hours, project_user_hours)
    |> assign(:total_time_worked, total_project_seconds)
    |> assign(:most_active_user, most_active_user)
  end

  def format_duration(0), do: "0 h 0 min"

  def format_duration(seconds) when seconds < 60 do
    "#{seconds} s"
  end

  def format_duration_with_days(0), do: "0 d 0 h 0 min"

  def format_duration_with_days(seconds) when seconds < 60 do
    "#{seconds} s"
  end

  defdelegate format_duration(seconds), to: TimeFormatter
  def format_duration_with_days(seconds), do: TimeFormatter.format_duration(seconds, :with_days)

  attr :project_user_hours, :list, required: true

  defp render_project_user_hours(assigns) do
    ~H"""
    <%= for user <- @project_user_hours do %>
      <div class="flex flex-col divide-y divide-greyButtonBg px-4 rounded-md bg-white col-span-full">
        <div class={
          classes([
            "flex items-center py-4 gap-6",
            user.removed_from_project && "bg-white/50 border border-greyButtonBg/50"
          ])
        }>
          <.render_profile user={user} />
          <span :if={!user.expanded} class="ml-auto">{trunc(user.time_worked / 60 / 60)} h</span>

          <button
            phx-click="toggle-user"
            phx-value-id={user.id}
            disabled={user.time_worked == 0}
            class="disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <.icon :if={user.expanded} name="hero-chevron-up-mini" class="text-darkGrey" />
            <.icon :if={!user.expanded} name="hero-chevron-down-mini" class="text-darkGrey" />
          </button>
        </div>

        <div :if={user.expanded} class="space-y-4 py-4 pr-11">
          <div :for={session <- user.sessions} class="flex justify-between text-sm">
            <span>{session.title}</span>
            <span>{TimeFormatter.format_duration(session.duration)}</span>
          </div>
        </div>
      </div>
    <% end %>

    <div class="hidden only:block py-8 bg-white rounded-md text-center text-darkGrey text-sm col-span-full">
      Brak danych o czasie pracy dla tego projektu.
    </div>
    """
  end

  attr :project_users, :list, required: true
  attr :users, :list, required: true

  defp render_project_edit(assigns) do
    ~H"""
    <%= for user <- @project_users do %>
      <div class="flex items-center bg-white rounded-md p-4 justify-between col-span-full">
        <.render_profile user={user} />
        <button
          phx-click="delete_user"
          phx-value-user_id={user.id}
          class="h-6 w-8 rounded-md hover:bg-greyButtonBg text-darkGrey disabled:text-orangeText inline-flex items-center justify-center ml-1"
        >
          <.icon name="hero-trash-micro" />
        </button>
      </div>
    <% end %>

    <form phx-change="add_user" class="relative w-[35%] ">
      <.icon
        name="hero-plus-mini"
        class="text-darkGrey absolute top-1/2 transform -translate-y-1/2 left-2"
      />
      <.input
        type="select"
        name="user_id"
        id="user"
        prompt="Dodaj współpracownika"
        value={nil}
        options={Enum.map(@users, &{&1.name || &1.email, &1.id})}
        class="pl-9"
      />
    </form>
    """
  end

  attr :hours_records, :list, required: true
  attr :editing_employee_salaries, :map, required: true
  attr :employee_salary_forms, :map, required: true

  defp render_employee_edit(assigns) do
    ~H"""
    <%= for record <- @hours_records do %>
      <% user = record.user %>
      <div class="flex flex-row col-span-full gap-4">
        <div class="flex flex-col flex-grow rounded-md bg-white">
          <div class="flex items-center justify-between p-4">
            <div class="flex items-center">
              <.render_profile user={user} />
            </div>
          </div>
          
    <!-- separator -->
          <div class="h-px bg-greyButtonBg mx-2"></div>

          <.live_component
            module={FirmowidWeb.Components.Timetracker.UserProfileSummary}
            id={"user_summary_#{user.id}"}
            user={user}
            user_hours={record.user_hours}
          />
        </div>

        <%= if !Map.get(@editing_employee_salaries, user.id, false) do %>
          <div class="bg-white rounded-md p-4 w-1/4 ml-4 flex flex-col justify-between">
            <div class="text-md font-medium text-darkGrey text-center mb-2">Stawka godzinowa</div>
            <div class="flex flex-col w-full mt-auto px-2">
              <div class="text-center text-lg py-1 mb-2 border border-greyButtonBg rounded-md bg-lightGreyBg ">
                {format_hourly_rate(get_current_hourly_rate(user))}
              </div>
              <.button
                type="button"
                color="light_grey"
                class="w-full py-2"
                phx-click="edit_employee_salary"
                phx-value-user_id={user.id}
              >
                Edytuj
              </.button>
            </div>
          </div>
        <% else %>
          <% form_values =
            case user.current_salary do
              nil ->
                %{"hourly_rate" => "", "fixed_salary" => "", "salary_type" => "hourly"}

              salary ->
                hourly_rate_str = Decimal.to_string(salary.hourly_rate)
                fixed_salary = Decimal.mult(salary.hourly_rate, Decimal.new("168"))
                fixed_salary_str = Decimal.to_string(fixed_salary)

                %{
                  "hourly_rate" => hourly_rate_str,
                  "fixed_salary" => fixed_salary_str,
                  "salary_type" => "hourly"
                }
            end

          user_form =
            Map.get(@employee_salary_forms, user.id) ||
              to_form(EmployeeSalaryForm.changeset(form_values),
                as: "employee_salary_form_#{user.id}"
              ) %>
          <.form
            for={user_form}
            phx-change="validate_employee_salary"
            phx-submit="save_employee_salary"
            phx-value-user_id={user.id}
            class="bg-white rounded-md p-4 w-1/4 flex flex-col justify-between ml-4 !mt-0"
          >
            <.radio_group field={user_form[:salary_type]} class="flex flex-row justify-center">
              <:radio value="fixed">Stała</:radio>
              <:radio value="hourly">Godzinowa</:radio>
            </.radio_group>
            <div class="flex flex-col w-full px-2">
              <div
                :if={user_form[:salary_type] && user_form[:salary_type].value == "hourly"}
                class="flex flex-row items-center py-1 mb-2 border border-greyButtonBg rounded-md text-darkGrey focus-within:border-blueText"
              >
                <div class="flex flex-row ">
                  <.input
                    type="number"
                    field={user_form[:hourly_rate]}
                    input_class="!bg-transparent !border-0 !py-0 !pl-0 !pr-2 !text-lg !text-right [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    step="0.01"
                    min="0"
                  />
                </div>
                <div class="text-lg text-right pr-2">PLN/h</div>
              </div>
              <div
                :if={user_form[:salary_type] && user_form[:salary_type].value == "fixed"}
                class="flex flex-row items-center py-1 mb-2 border border-greyButtonBg rounded-md text-darkGrey focus-within:border-blueText"
              >
                <div class="flex flex-row">
                  <.input
                    type="number"
                    field={user_form[:fixed_salary]}
                    input_class="!bg-transparent !border-0 !py-0 !pl-0 !pr-2 !text-lg !text-right [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    step="0.01"
                    min="0"
                  />
                </div>
                <div class="text-lg text-right pr-2">PLN</div>
              </div>
              <div class="flex gap-2">
                <.button type="submit" color="light_orange" class="flex-1 py-1">
                  Zapisz
                </.button>
                <.button
                  type="button"
                  color="light_grey"
                  class="flex-1 py-2"
                  phx-click="cancel_edit_employee_salary"
                  phx-value-user_id={user.id}
                >
                  Anuluj
                </.button>
              </div>
            </div>
          </.form>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :hours_records, :list, required: true

  defp render_hours_records(assigns) do
    ~H"""
    <%= for %{user: user, hours_record: record, expanded: expanded, user_hours: user_hours} <- @hours_records do %>
      <div class="grid grid-cols-subgrid col-span-full">
        <div class="flex flex-col bg-white rounded-md">
          <div class="flex items-center p-4 justify-between">
            <.render_profile user={user} />
            <span :if={record}>{trunc(record.number_of_hours)} h</span>
            <button
              phx-click="toggle-user-summary"
              phx-value-id={user.id}
              class="disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <span class="ml-auto">{trunc(user_hours.time_worked / 60 / 60)} h</span>
              <.icon :if={expanded} name="hero-chevron-up-mini" class="text-darkGrey" />
              <.icon :if={!expanded} name="hero-chevron-down-mini" class="text-darkGrey" />
            </button>
          </div>

          <div :if={expanded}>
            <div class="h-px bg-greyButtonBg mx-2"></div>
            <.live_component
              module={FirmowidWeb.Components.Timetracker.UserProfileSummary}
              id={"user_summary_#{user.id}"}
              user={user}
              user_hours={user_hours}
            />
          </div>
        </div>

        <div class="bg-white rounded-md p-4 justify-between items-center flex gap-5 self-start">
          <%= if record do %>
            <span class="text-xs font-semibold text-greenText bg-greenBg pl-2 pr-1 py-[5px] uppercase rounded-md flex items-center justify-between flex-1 gap-1">
              EWIDENCJA <.icon name="hero-check-micro" />
            </span>
            <a
              href={~p"/czasosledz/ewidencja/#{record.id}"}
              download={"Ewidencja_#{record.year}_#{record.month}_#{user.name || user.email}.pdf"}
              class="p-1 transition hover:bg-greyButtonBg rounded-md inline-flex items-center justify-center"
            >
              <.icon name="hero-arrow-down-tray-mini" class="text-darkGrey" />
            </a>
          <% else %>
            <span class="text-xs font-semibold text-darkGrey bg-greyButtonBg px-2 py-[5px] uppercase rounded-md flex items-center justify-between flex-1 gap-1">
              BRAK <.icon name="hero-x-mark-micro" />
            </span>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="stroke-greyButtonBg shrink-0 m-0.5"
            >
              <path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z" /><path d="m14.5 12.5-5 5" /><path d="m9.5 12.5 5 5" />
            </svg>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  attr :user, :map, required: true

  defp render_profile(assigns) do
    ~H"""
    <div class="flex items-center gap-6">
      <.avatar class="size-8 ring-1 ring-greyButtonBg/50">
        <.avatar_image src={@user.avatar_url} alt="Avatar" />
        <.avatar_fallback class="bg-blueBg text-blueText">
          {String.slice(@user.name || @user.email || "", 0, 1) |> String.upcase()}
        </.avatar_fallback>
      </.avatar>
      <span class="text-darkGrey">
        {@user.name || @user.email}
      </span>
    </div>
    """
  end
end
