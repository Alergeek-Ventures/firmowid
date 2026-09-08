defmodule FirmowidWeb.Management.Views.Delegation do
  @moduledoc "Management view for preparing an employee's business-trip order."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.Delegation, only: [detail_row: 1]
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Delegations
  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Management.Utilities.Navigation

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :command_form, command_form(false))}
  end

  @impl true
  def handle_params(%{"id" => employee_id, "delegation_id" => delegation_id}, _uri, socket) do
    scope = socket.assigns.ash_scope

    case Core.get_org_user!(%{id: employee_id}, scope: scope, not_found_error?: false) do
      nil ->
        {:noreply, push_navigate(socket, to: Navigation.employees_path(:index))}

      employee ->
        delegation =
          employee_id
          |> Delegations.list_delegations_for_user!(scope: scope)
          |> Enum.find(&(&1.id == delegation_id))

        if delegation do
          {:noreply,
           socket
           |> assign(:employee, employee)
           |> assign(:delegation, delegation)
           |> assign(:page_title, "Polecenie wyjazdu służbowego")}
        else
          {:noreply, push_navigate(socket, to: Navigation.employee_path(employee.id))}
        end
    end
  end

  @impl true
  def handle_event("toggle-advance", %{"delegation_command" => %{"advance" => value}}, socket) do
    {:noreply, assign(socket, :command_form, command_form(value == "true"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto w-full max-w-7xl p-6 lg:px-12">
      <.back navigate={Navigation.employee_path(@employee.id)} class="justify-self-start">
        Profil pracownika
      </.back>

      <h1 class="mt-10 text-2xl/tight font-normal">Polecenie wyjazdu służbowego</h1>

      <div class="mt-10 grid grid-cols-1 items-start gap-10 lg:grid-cols-2">
        <section>
          <p class="text-grey-700 max-w-xl text-base text-balance">
            Poniżej znajdziesz szczegóły delegacji zgłoszonej przez pracownika. Na tej podstawie ustal, czy przysługuje mu zaliczka, a następnie wygeneruj polecenie.
          </p>

          <dl class="mt-8 grid grid-cols-[minmax(10rem,auto)_1fr] gap-x-8 gap-y-5">
            <.detail_row label="Imię i nazwisko">{@employee.name || @employee.email}</.detail_row>
            <.detail_row label="Stanowisko">{@employee.position || "—"}</.detail_row>
            <.detail_row label="Data wyjazdu">
              {DelegationPresentation.format_range(@delegation.start_date, @delegation.end_date)}
            </.detail_row>
            <.detail_row label="Cel wyjazdu">{@delegation.purpose}</.detail_row>
            <.detail_row label="Przewidywana kwota">
              {Money.to_string!(@delegation.advance_payment_amount)}
            </.detail_row>
          </dl>

          <.form
            for={@command_form}
            id="delegation-command-form"
            phx-change="toggle-advance"
            class="mt-10 space-y-5"
          >
            <.switch field={@command_form[:advance]} label="Zaliczka" color="turquoise" />

            <div>
              <label for={@command_form[:amount].id} class="text-grey-700 text-base">Na kwotę</label>
              <div class="mt-2 flex items-center gap-2">
                <.input
                  field={@command_form[:amount]}
                  type="number"
                  new
                  min="0"
                  step="0.01"
                  placeholder="0.00"
                  disabled={not @command_form[:advance].value}
                  aria-describedby="delegation-command-currency"
                  input_class="w-25 text-right placeholder:text-grey-300"
                />
                <span id="delegation-command-currency" class="text-grey-500 text-sm">PLN</span>
              </div>
            </div>

            <.button type="button" variant="primary" accent="turquoise" size="small">
              Wygeneruj polecenie
            </.button>
          </.form>
        </section>

        <section>
          <dl class="grid grid-cols-[auto_1fr] gap-x-6 text-base">
            <dt class="text-grey-700">Miesiąc rozliczeniowy</dt>
            <dd>{format_billing_month(@delegation.billing_month)}</dd>
          </dl>

          <div class="border-grey-200 mt-8 flex min-h-96 items-center justify-center rounded-md border bg-white p-8 text-center shadow-sm">
            <p class="text-grey-700 max-w-xs text-base">Wygeneruj polecenie, aby móc je podpisać.</p>
          </div>

          <div class="mt-5 flex gap-3">
            <.button type="button" variant="destructive" size="small">Odrzuć</.button>
            <.button type="button" variant="primary" accent="turquoise" size="small">Wyślij</.button>
          </div>
        </section>
      </div>
    </main>
    """
  end

  defp command_form(advance?) do
    to_form(%{"advance" => advance?, "amount" => ""}, as: :delegation_command)
  end

  defp format_billing_month(billing_month) do
    Cldr.Date.to_string!(billing_month, Firmowid.Cldr, format: "MMMM y", locale: "pl")
  end
end
