defmodule FirmowidWeb.Management.Views.Employees do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.EmptyState
  import FirmowidWeb.DesignSystem.Components.Fields, only: [search_field: 1]
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.DesignSystem.Components.Tooltip
  import FirmowidWeb.HoursRecord.Components.Status, only: [hours_record_status: 1]
  import FirmowidWeb.Inbox.Components.Queue, only: [office_panel: 1]
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Management.Components.Roles
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Invalid
  alias Ash.Notifier.Notification
  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Core.UserRole
  alias Firmowid.Payroll
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Management.Utilities.Navigation
  alias FirmowidWeb.Payroll.Components.MonthlyPayout
  alias FirmowidWeb.Payroll.Components.PayoutEstimates
  alias FirmowidWeb.Timetracker.Utilities.Navigation, as: TimetrackerNavigation
  alias Phoenix.Socket.Broadcast

  on_mount {FirmowidWeb.Infrastructure.Hooks.RequireAdmin, :default}

  @invite_load [issued_by: [:email]]

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope
    active_months = Timetracker.months_with_sessions(%{}, scope)

    if connected?(socket) do
      Endpoint.subscribe("user:joined_org:#{scope.tenant}")
      Endpoint.subscribe("blob:updated:#{scope.tenant}")
    end

    socket =
      socket
      |> assign(:page_title, gettext("Employee management"))
      # The page spaces itself, as in the design (see `employees.html.heex`).
      |> assign(:no_padding, true)
      |> assign(:view, :standard)
      |> assign(:active_months, active_months)
      |> assign(
        :editable_months,
        [Date.beginning_of_month(Date.utc_today())]
      )
      |> assign(:selected_user, nil)
      # Who works today, beside the table on wide screens.
      |> assign(:presence, Session.team_presence!(Date.utc_today(), scope: scope))
      |> assign_invites()
      |> assign_form()

    {:ok, socket}
  end

  @impl true
  # Joining uses up the invitation, so it leaves the active ones too.
  def handle_info(%Broadcast{topic: "user:joined_org:" <> _tenant}, socket) do
    {:noreply, socket |> assign_employees() |> assign_invites()}
  end

  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            data: %{processing_target: :employment_contract, processing_state: :succeeded}
          }
        },
        socket
      ) do
    {:noreply, assign_employees(socket)}
  end

  def handle_info(%Broadcast{topic: "blob:updated:" <> _tenant}, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    params = Navigation.employees_params(params)
    selected_date = Navigation.parse_month(params)

    disable_editing =
      selected_date not in socket.assigns.editable_months and socket.assigns.view == :wage_editor

    socket =
      socket
      |> assign(:params, params)
      |> assign(:selected_date, selected_date)
      |> assign(:search, params["szukaj"] || "")
      |> assign_employees()
      |> assign(
        :view,
        cond do
          # The archive shows no payroll, so its switch is off and disabled.
          socket.assigns.live_action == :archive -> :standard
          disable_editing -> :wages
          true -> socket.assigns.view
        end
      )
      |> assign_form()

    {:noreply, socket}
  end

  defp assign_employees(%{assigns: %{selected_date: date, search: search, ash_scope: scope}} = socket) do
    # 1. Users (with optional search filter)
    list_filters =
      case socket.assigns.live_action do
        :index -> %{status: :active}
        :archive -> %{status: :archived}
      end

    search_filters = if search in [nil, ""], do: %{}, else: %{search: search}
    input = Map.merge(list_filters, search_filters)

    users = Core.list_users!(input, scope: scope, load: [member: [avatar_blob: [:url]]])

    # 2. Time worked per member this month
    time_by_member =
      %{month: date.month, year: date.year}
      |> Timetracker.list_sessions!(scope: scope)
      |> Enum.group_by(& &1.member_id, & &1.duration)
      |> Map.new(fn {member_id, durations} -> {member_id, Enum.sum(durations)} end)

    # 3. Salaries as of this month]
    salaries =
      Payroll.list_salaries!(%{active_at: Date.end_of_month(date)},
        load: [monthly_amount: [month: date], monthly_payout: [month: date]],
        scope: scope
      )

    salary_by_member = Map.new(salaries, &{&1.member_id, &1.hourly_rate})
    payout_by_member = Map.new(salaries, &{&1.member_id, &1.monthly_payout})
    gross_by_member = Map.new(salaries, &{&1.member_id, &1.monthly_amount})

    # 4. Hours records for this month
    hr_by_member =
      %{month: date.month, year: date.year}
      |> Timetracker.list_hours_records!(scope: scope)
      |> Map.new(&{&1.member_id, &1})

    # 5. Compose
    employees =
      users
      |> Enum.map(fn user ->
        %{
          user: user,
          time_worked: Map.get(time_by_member, user.member.id, 0),
          hourly_rate: Map.get(salary_by_member, user.member.id),
          monthly_gross: Map.get(gross_by_member, user.member.id, Money.new!(:PLN, 0)),
          monthly_payout: Map.get(payout_by_member, user.member.id),
          hours_record: Map.get(hr_by_member, user.member.id)
        }
      end)
      |> Enum.sort_by(fn employee ->
        name = employee.user.member.name || to_string(employee.user.email)
        {employee.time_worked == 0, String.downcase(name)}
      end)

    assign(socket, :employees, employees)
  end

  defp assign_invites(socket) do
    invites =
      active_invites(Core.list_invites!(load: @invite_load, scope: socket.assigns.ash_scope))

    assign(socket, :invites, invites)
  end

  # Roles show in the active list while the wages are hidden.
  defp roles_column?(assigns) do
    assigns.view == :standard and assigns.live_action == :index
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(%{"viewing_wages" => socket.assigns.view != :standard}))
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

    # The rate goes to the action as typed, so a cleared field fails its validation.
    entries =
      Enum.flat_map(socket.assigns.employees, fn employee ->
        hourly_rate = employees_params[employee.user.id]["wage"]

        if same_rate?(employee.hourly_rate, hourly_rate),
          do: [],
          else: [%{member_id: employee.user.member.id, hourly_rate: hourly_rate}]
      end)

    case Payroll.bulk_create_salaries(entries, scope: scope) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:view, :wages)
         |> PosthogBusinessEvents.capture(
           :payroll_rates_updated,
           %{changed_employee_count: length(entries)}
         )
         |> push_event("unsaved-changed", %{value: false})
         |> assign_employees()}

      {:error, error} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not update the rates: %{error}", error: error_message(error))
         )}
    end
  end

  def handle_event("search", %{"szukaj" => search}, socket) do
    params = Map.put(socket.assigns.params, "szukaj", search)

    {:noreply, push_patch(socket, to: Navigation.employees_path(socket.assigns.live_action, params))}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    params = Map.put(socket.assigns.params, "miesiac", month)

    {:noreply, push_patch(socket, to: Navigation.employees_path(socket.assigns.live_action, params))}
  end

  def handle_event("unarchive_employee", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    with {:ok, user} <-
           Core.get_org_user(%{id: id}, scope: scope, load: [:member], not_found_error?: false),
         {:ok, _member} <- Core.unarchive_member(user.member, scope: scope) do
      {:noreply, assign_employees(socket)}
    else
      {:error, %Invalid{errors: [%{message: message} = error | _]}}
      when is_binary(message) ->
        {:noreply, put_flash(socket, :error, Inputs.translate_error({message, Map.get(error, :vars, [])}))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not restore the employee"))}
    end
  end

  def handle_event("create_organization_invite", %{"role" => role_param}, socket) do
    case UserRole.from_param(role_param) do
      {:ok, role} ->
        invite =
          Core.create_invite!(%{issued_by_id: socket.assigns.current_user.id, role: role},
            scope: socket.assigns.ash_scope
          )

        {:noreply,
         socket
         |> assign_invites()
         |> push_event("copy-to-clipboard", %{text: invite.invite_code})
         |> LiveToast.put_toast(
           :success,
           gettext("The invitation code has been generated and copied to the clipboard.")
         )}

      {:error, :unknown_role} ->
        {:noreply, LiveToast.put_toast(socket, :error, gettext("Invalid role."))}
    end
  end

  def handle_event("copy_organization_invite", %{"code" => invite_code}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: invite_code})
     |> LiveToast.put_toast(
       :info,
       gettext("The invitation code has been copied to the clipboard.")
     )}
  end

  def handle_event("delete_organization_invite", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    # Deleted or used in another tab: already gone, so only the list refreshes.
    if invite = Core.get_invite!(id, scope: scope, not_found_error?: false) do
      Core.destroy_invite!(invite, scope: scope)
    end

    {:noreply,
     socket
     |> assign_invites()
     |> LiveToast.put_toast(:info, gettext("The invitation has been deleted."))}
  end

  def handle_event("open_update_role_modal", %{"user_id" => user_id}, socket) do
    # The list may be stale, e.g. the member was archived in another tab.
    case Enum.find(socket.assigns.employees, &(&1.user.id == user_id)) do
      %{user: user} ->
        {:noreply, assign(socket, :selected_user, user)}

      nil ->
        {:noreply,
         LiveToast.put_toast(
           socket,
           :error,
           gettext("The user was not found in the organization.")
         )}
    end
  end

  def handle_event("clear_selected_user", _params, socket) do
    {:noreply, assign(socket, :selected_user, nil)}
  end

  # The member comes from the opened modal, not from the submitted user_id.
  def handle_event("update_user_role", %{"role" => role_param}, %{assigns: %{selected_user: %{} = user}} = socket) do
    socket = assign(socket, :selected_user, nil)

    with {:ok, role} <- UserRole.from_param(role_param),
         {:ok, _member} <-
           Core.update_member_role(user.member, %{role: role}, scope: socket.assigns.ash_scope) do
      {:noreply,
       socket
       |> assign_employees()
       |> LiveToast.put_toast(:success, gettext("The user's role has been changed."))}
    else
      {:error, :unknown_role} ->
        {:noreply, LiveToast.put_toast(socket, :error, gettext("Unknown user role."))}

      {:error, _error} ->
        {:noreply, LiveToast.put_toast(socket, :error, gettext("Could not change the user's role."))}
    end
  end

  # A second submit after the dialog closed has no member to change.
  def handle_event("update_user_role", _params, socket), do: {:noreply, socket}

  def handle_event("copy-bank-number", %{"number" => number}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: number})
     |> LiveToast.put_toast(:success, gettext("Bank account number copied"))}
  end

  attr :selected_date, Date, required: true
  attr :active_months, :list, required: true
  attr :search, :string, required: true
  slot :inner_block, doc: "Controls between the month and the search, such as the list scope."

  defp month_and_search(assigns) do
    ~H"""
    <form class="flex items-center gap-4 max-md:flex-wrap max-md:gap-3" phx-submit="search">
      <.month_picker
        id="month"
        show_on_mobile
        selected_date={@selected_date}
        active_months={@active_months}
        class="max-md:flex-1"
      />

      {render_slot(@inner_block)}

      <%!-- Figma "Wyszukiwarka rozwijana": a square tertiary button that widens into the search
           field with focus, and narrows back when the field is left empty. The field itself is
           the button: collapsed, it takes the button's fill and its thicker magnifier, and a
           transparent button over it catches the click. The hook keeps the state, so the
           server's answers to typing do not collapse the field. --%>
      <div
        id="search-container"
        phx-hook=".ExpandingSearch"
        phx-update="ignore"
        data-expanded={to_string(@search != "")}
        class="group relative w-9 overflow-hidden rounded-sm transition-[width] duration-300 ease-out data-[expanded=true]:w-60 max-md:data-[expanded=true]:w-full data-[expanded=false]:[&_input]:border-transparent data-[expanded=false]:[&_input]:bg-grey-200 data-[expanded=false]:[&_input]:placeholder:text-transparent data-[expanded=false]:hover:[&_input]:bg-grey-300 data-[expanded=false]:[&_svg]:stroke-[2.4] data-[expanded=false]:[&_svg]:text-grey-900"
      >
        <.search_field
          name="szukaj"
          value={@search}
          placeholder={gettext("Search employees")}
          size="medium"
          autocomplete="off"
          tabindex={if(@search == "", do: "-1")}
          phx-change="search"
          phx-debounce="300"
          class="w-60 max-md:w-full"
        />
        <.button
          type="button"
          variant="unstyled"
          data-expand
          class="absolute inset-0 cursor-pointer rounded-sm group-data-[expanded=true]:hidden"
        >
          <span class="sr-only">{gettext("Search employees")}</span>
        </.button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".ExpandingSearch">
          export default {
            mounted() {
              const input = this.el.querySelector("input");
              this.el.querySelector("[data-expand]").addEventListener("click", () => {
                this.el.dataset.expanded = "true";
                input.tabIndex = 0;
                input.focus();
              });
              input.addEventListener("blur", () => {
                if (input.value !== "") return;
                this.el.dataset.expanded = "false";
                input.tabIndex = -1;
              });
            }
          }
        </script>
      </div>
    </form>
    """
  end

  attr :selected_date, Date, required: true

  defp header_actions(assigns) do
    ~H"""
    <div class="flex gap-3 max-md:contents">
      <.link
        kind="button"
        variant="tertiary"
        size="big"
        download
        redirect={TimetrackerNavigation.salaries_csv_path(@selected_date)}
        class="max-md:hidden"
      >
        <Lucideicons.file_text /> {gettext("Payroll report")}
      </.link>
      <.page_actions>
        <:action>
          <.button
            type="button"
            variant="special"
            phx-click={show_modal("organization_invite_modal")}
            data-fab
          >
            <.icon name="hero-plus-mini" class="size-6" />
            <span class="max-md:sr-only">{gettext("Add employee")}</span>
          </.button>
        </:action>
      </.page_actions>
    </div>
    """
  end

  attr :selected_date, Date, required: true
  attr :employees, :list, required: true
  attr :wages?, :boolean, required: true
  attr :accurate?, :boolean, required: true

  # Figma "Ten miesiąc": the listed month in numbers, beside the table on wide screens. The payroll
  # view swaps the average and the timesheets for the money.
  defp month_summary(assigns) do
    hours = assigns.employees |> Enum.map(& &1.time_worked) |> Enum.sum() |> div(3600)
    count = length(assigns.employees)

    rows =
      if assigns.wages? do
        [
          {gettext("Hours worked"), hours_label(hours)},
          {pgettext("team month", "Gross total"), total_gross(assigns.employees, assigns.accurate?)},
          {pgettext("team month", "To pay in total"), if(assigns.accurate?, do: total_payout(assigns.employees)) || "—"}
        ]
      else
        [
          {gettext("Hours worked"), hours_label(hours)},
          {pgettext("team month", "Average per person"), hours_label(if(count > 0, do: round(hours / count), else: 0))},
          {pgettext("team month", "Timesheets submitted"),
           pgettext("team month", "%{count} of %{total}",
             count: Enum.count(assigns.employees, & &1.hours_record),
             total: count
           )}
        ]
      end

    assigns = assign(assigns, rows: rows)

    ~H"""
    <section class="flex flex-col gap-4 rounded-sm bg-white p-5">
      <h2 class="text-caps-sm font-medium text-grey-600 uppercase">
        {Firmowid.Cldr.Date.to_string!(@selected_date, format: "LLLL y")}
      </h2>
      <dl class="flex flex-col gap-2">
        <div :for={{label, value} <- @rows} class="flex items-baseline justify-between gap-3 text-sm">
          <dt class="truncate leading-[1.35] text-grey-700">{label}</dt>
          <dd class="shrink-0 font-medium text-grey-900 tabular-nums">{value}</dd>
        </div>
      </dl>
    </section>
    """
  end

  defp hours_label(hours), do: "#{hours} #{hours_unit()}"

  # Hours read "godz.", as in the design; the shorter units keep the formatter's labels.
  defp hours_unit, do: pgettext("hours worked unit", "hrs")

  defp total_gross(employees, true) do
    employees
    |> Enum.map(&(&1.monthly_payout && &1.monthly_payout.gross))
    |> sum_money()
  end

  defp total_gross(employees, false), do: employees |> Enum.map(& &1.monthly_gross) |> sum_money()

  # Only the calculated payouts add up; with none calculated there is no total.
  defp total_payout(employees) do
    case employees
         |> Enum.map(&MonthlyPayout.amount(&1.monthly_payout))
         |> Enum.reject(&is_nil/1) do
      [] -> nil
      amounts -> sum_money(amounts)
    end
  end

  defp sum_money(amounts) do
    amounts |> Enum.reject(&is_nil/1) |> Enum.reduce(Money.new!(:PLN, 0), &Money.add!/2)
  end

  # The shown rate field is as wide as its digits (tabular, one `ch` each).
  defp rate_width(rate), do: (rate || 0) |> Decimal.round() |> Decimal.to_string() |> String.length()

  defp same_rate?(nil, _typed), do: false

  defp same_rate?(current, typed) do
    case Decimal.parse(typed) do
      {rate, ""} -> Decimal.equal?(current, rate)
      _invalid -> false
    end
  end

  defp error_message(%Invalid{errors: [error | _]}) do
    [{_field, message, vars} | _] =
      error |> AshPhoenix.FormData.Error.to_form_error() |> List.wrap()

    Inputs.translate_error({message, vars})
  end

  defp error_message(error), do: Exception.message(error)
end
