defmodule FirmowidWeb.Management.Components.EmployeePayoutDetails do
  @moduledoc "LiveComponent with an employee's bank account, current hourly rate and rate history."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]
  import FirmowidWeb.Management.Components.Card

  alias Firmowid.Core
  alias Firmowid.Payroll
  alias Firmowid.TimeFormatter

  @impl true
  def mount(socket), do: {:ok, attach_access_hook(socket, :scope)}

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:editing, fn -> false end)
      |> assign_salaries()
      |> assign_form()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.card class="relative z-10" dimmed={@user.member.archived_at}>
        <.card_header>
          {gettext("Transfer details")}
          <:actions>
            <.card_edit_actions
              editing={@editing}
              form="payout-form"
              toggle_event="toggle_payout_editor"
              target={@myself}
              edit_label={gettext("Edit transfer details")}
            />
          </:actions>
        </.card_header>

        <.form
          id="payout-form"
          for={@form}
          phx-target={@myself}
          phx-submit="save_payout"
        >
          <div class="grid grid-cols-[minmax(min-content,2fr)_minmax(min-content,1fr)] gap-4">
            <.user_card_info
              label={gettext("Bank account number")}
              for={@form[:bank_account_number].id}
            >
              <%= if @editing do %>
                <.input
                  field={@form[:bank_account_number]}
                  type="text"
                  class="w-full"
                />
              <% else %>
                {@user.member.bank_account_number || gettext("No data")}
              <% end %>
            </.user_card_info>
            <div class="flex items-end justify-between gap-4">
              <%= if @editing do %>
                <.user_card_info
                  label={gettext("New rate")}
                  for={@form[:hourly_rate].id}
                  class="text-nowrap"
                >
                  <div class="flex items-center gap-2">
                    <.input
                      field={@form[:hourly_rate]}
                      type="number"
                      step="0.01"
                      min="0"
                      input_class="max-w-20 text-right"
                    />
                    <p>{gettext("PLN/h")}</p>
                  </div>
                </.user_card_info>
              <% else %>
                <.user_card_info label={pgettext("hourly rate", "Rate")} class="text-nowrap">
                  <div class="min-h-8.5">
                    {gettext("%{amount}/h",
                      amount:
                        Money.new(:PLN, @hourly_rate)
                        |> Money.to_string!(no_fraction_if_integer: true)
                    )}
                  </div>
                </.user_card_info>
                <.button
                  type="button"
                  variant="outline"
                  size="small"
                  phx-click={show_modal("salary-history-modal")}
                  disabled={Enum.empty?(@salary_history)}
                  class="self-center"
                >
                  {gettext("Rate history")}
                </.button>
              <% end %>
            </div>
          </div>
        </.form>
      </.card>

      <.modal id="salary-history-modal">
        <h2 class="mb-4 text-xl font-medium">{gettext("Rate history")}</h2>
        <div class="flex scrollbar-card max-h-[400px] flex-col gap-2 divide-grey-100 overflow-y-auto">
          <%= if Enum.empty?(@salary_history) do %>
            <p class="text-grey-700">{gettext("No data")}</p>
          <% else %>
            <div :for={salary <- @salary_history} class="flex items-end gap-2">
              <span>
                {gettext("%{amount}/h",
                  amount:
                    :PLN
                    |> Money.new(salary.hourly_rate)
                    |> Money.to_string!(no_fraction_if_integer: true)
                )}
              </span>
              <span class="text-sm text-grey-500">
                ({TimeFormatter.format_date(salary.starts_at)} - {if salary.ends_at,
                  do: TimeFormatter.format_date(salary.ends_at),
                  else: pgettext("salary period end", "present")})
              </span>
            </div>
          <% end %>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_payout_editor", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, not socket.assigns.editing)
     |> assign_form()}
  end

  def handle_event("save_payout", %{"hourly_rate" => hourly_rate, "bank_account_number" => bank_account_number}, socket) do
    {:noreply,
     socket
     |> save_hourly_rate(hourly_rate)
     |> save_bank_account(bank_account_number)
     |> assign(:editing, false)
     |> assign_form()}
  end

  defp assign_salaries(socket) do
    %{user: user, scope: scope} = socket.assigns

    hourly_rate =
      %{user_id: user.id, active_at: Date.utc_today()}
      |> Payroll.list_salaries!(scope: scope)
      |> case do
        [] -> Decimal.new(0)
        [salary | _] -> salary.hourly_rate
      end

    socket
    |> assign(:hourly_rate, hourly_rate)
    |> assign(
      :salary_history,
      Payroll.list_salaries!(%{user_id: user.id}, scope: scope, load: [:ends_at])
    )
  end

  defp save_hourly_rate(socket, hourly_rate) do
    %{user: user, scope: scope} = socket.assigns

    case Payroll.create_salary(%{hourly_rate: hourly_rate, member_id: user.member.id},
           scope: scope
         ) do
      {:ok, _salary} -> assign_salaries(socket)
      {:error, _} -> put_flash(socket, :error, gettext("Could not save the rate. Try again."))
    end
  end

  defp save_bank_account(socket, bank_account_number) do
    %{user: user, scope: scope} = socket.assigns

    case Core.update_member_profile(user.member, %{bank_account_number: bank_account_number}, scope: scope) do
      {:ok, member} ->
        updated_user = %{user | member: member}
        send(self(), {:employee_updated, updated_user})
        assign(socket, :user, updated_user)

      {:error, _} ->
        put_flash(socket, :error, gettext("Could not save the bank account number. Try again."))
    end
  end

  defp assign_form(socket) do
    %{hourly_rate: hourly_rate, user: user} = socket.assigns

    assign(
      socket,
      :form,
      to_form(%{
        "hourly_rate" => hourly_rate,
        "bank_account_number" => user.member.bank_account_number
      })
    )
  end
end
