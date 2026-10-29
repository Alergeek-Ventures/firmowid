defmodule FirmowidWeb.Management.Components.ProfileTab do
  @moduledoc "LiveComponent for displaying employee profile information."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Link
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Management.Components.Card
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Payroll
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # `send_update/3` passes only the new assigns; the employee view's refetch
    # after contract processing has neither the user nor the scope.
    socket = assign(socket, Map.delete(assigns, :refetch))
    %{user: user, scope: scope} = socket.assigns

    {:ok, employment_contract} = Payroll.load_current_contract(user.member.id, scope: scope)

    socket =
      socket
      |> assign_new(:editing_contract, fn -> false end)
      |> assign_contract(employment_contract)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col gap-6 overflow-y-auto overscroll-contain">
      <.card dimmed={@user.member.archived_at} class="pb-9">
        <.card_header>
          Dane korespondencyjne
        </.card_header>
        <div class="grid grid-cols-2 gap-5 max-md:grid-cols-1">
          <div class="flex flex-col gap-5">
            <.user_card_info label="Numer telefonu">
              {present(@user.member.phone)}
            </.user_card_info>
            <.user_card_info label="Adres e-mail">
              {present(@user.email)}
            </.user_card_info>
            <.user_card_info label="Slack">
              {present(@user.member.slack_url) |> String.replace_prefix("https://", "")}
            </.user_card_info>
          </div>
          <div class="flex flex-col gap-5">
            <.user_card_info label="Adres zamieszkania">
              {present(@user.member.residence_address)}
            </.user_card_info>

            <.user_card_info :if={@user.member.correspondence_address} label="Adres korespondencyjny">
              {@user.member.correspondence_address}
            </.user_card_info>
          </div>
        </div>
      </.card>

      <.live_component
        module={FirmowidWeb.Management.Components.EmployeePayoutDetails}
        id={"employee-payout-details-#{@user.member.id}"}
        user={@user}
        scope={@scope}
      />

      <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,20rem),1fr))] items-start gap-6">
        <.card class="min-w-0">
          <.card_header>
            Informacje o zatrudnieniu
            <:actions>
              <.card_edit_actions
                :if={@employment_contract}
                editing={@editing_contract}
                form="contract-form"
                toggle_event="toggle_contract_editor"
                target={@myself}
                edit_label={gettext("Edit employment details")}
              />
            </:actions>
          </.card_header>
          <.form
            id="contract-form"
            for={@contract_form}
            phx-target={@myself}
            phx-submit="save_contract_employment"
          >
            <div class="flex flex-col gap-4">
              <%= if @editing_contract do %>
                <.user_card_info label="Status" for={@contract_form[:status].id}>
                  <.input
                    field={@contract_form[:status]}
                    container_class="w-full"
                    type="select"
                    options={[
                      {"Oczekuje na podpis", :pending_signature},
                      {"Podpisana", :signed},
                      {"Obowiązująca", :active}
                    ]}
                  />
                </.user_card_info>
                <.user_card_info label="Rodzaj umowy" for={@contract_form[:contract_type].id}>
                  <.input
                    field={@contract_form[:contract_type]}
                    container_class="w-full"
                    type="select"
                    options={[
                      {"Umowa o pracę", :uop},
                      {"B2B", :b2b},
                      {"Umowa zlecenie", :uz},
                      {"Umowa o dzieło", :uod}
                    ]}
                  />
                </.user_card_info>
                <.user_card_info label="Stanowisko" for={@contract_form[:position].id}>
                  <.input field={@contract_form[:position]} class="w-full" />
                </.user_card_info>
                <.user_card_info label="Data podpisania umowy" for={@contract_form[:signed_at].id}>
                  <.input field={@contract_form[:signed_at]} type="date" class="w-full" />
                </.user_card_info>
                <.user_card_info
                  :if={flag_enabled?(:accurate_salary_calculation, assigns)}
                  label={gettext("Payment day")}
                  for={@contract_form[:payout_day].id}
                >
                  <.input field={@contract_form[:payout_day]} type="number" min="1" max="31" step="1" />
                </.user_card_info>
                <.user_card_info
                  :if={flag_enabled?(:accurate_salary_calculation, assigns)}
                  label={gettext("Payment month")}
                  for={@contract_form[:payout_month_offset].id}
                >
                  <.input
                    field={@contract_form[:payout_month_offset]}
                    type="select"
                    options={[
                      {gettext("No information yet"), ""},
                      {gettext("Same month"), 0},
                      {gettext("Following month"), 1}
                    ]}
                  />
                </.user_card_info>
              <% else %>
                <.user_card_info label="Status umowy">
                  {format_contract_status(@employment_contract && @employment_contract.status)}
                </.user_card_info>
                <.user_card_info label="Rodzaj umowy">
                  {format_contract_type(@employment_contract && @employment_contract.contract_type)}
                </.user_card_info>
                <.user_card_info label="Stanowisko">
                  {present(@employment_contract && @employment_contract.position)}
                </.user_card_info>
                <.user_card_info label="Data podpisania umowy">
                  {present_date(@employment_contract && @employment_contract.signed_at)}
                  <.link
                    :if={@employment_contract}
                    kind="button"
                    variant="outline"
                    size="small"
                    class="ml-auto"
                    redirect={~p"/zarzadzanie/umowy/#{@employment_contract.id}"}
                    download
                  >
                    <Lucideicons.file_text class="size-4" /> <span class="font-medium">Umowa</span>
                  </.link>
                </.user_card_info>
                <.user_card_info
                  :if={flag_enabled?(:accurate_salary_calculation, assigns)}
                  label={gettext("Payment schedule")}
                >
                  {payout_schedule(@employment_contract)}
                </.user_card_info>
              <% end %>
            </div>
          </.form>
        </.card>

        <.live_component
          :if={flag_enabled?(:accurate_salary_calculation, assigns)}
          module={FirmowidWeb.Management.Components.EmployeeTaxDetails}
          id={"employee-tax-details-#{@user.member.id}"}
          member_id={@user.member.id}
          scope={@scope}
          contract_type={@employment_contract && @employment_contract.contract_type}
          archived={not is_nil(@user.member.archived_at)}
        />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_contract_editor", _params, socket) do
    {:noreply,
     socket
     |> update(:editing_contract, &(!&1))
     |> assign(
       :contract_form,
       contract_form(socket.assigns.employment_contract, socket.assigns.scope)
     )}
  end

  def handle_event("save_contract_employment", %{"contract" => params}, socket) do
    params =
      if flag_enabled?(:accurate_salary_calculation, socket.assigns),
        do: params,
        else: Map.drop(params, ["payout_day", "payout_month_offset"])

    case AshPhoenix.Form.submit(socket.assigns.contract_form,
           params: params,
           scope: socket.assigns.scope
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:editing_contract, false)
         |> assign_contract(updated)}

      {:error, form} ->
        {:noreply, assign(socket, :contract_form, form)}
    end
  end

  defp format_contract_type(nil), do: "Nieokreślony"
  defp format_contract_type(:uop), do: "Umowa o pracę"
  defp format_contract_type(:b2b), do: "B2B"
  defp format_contract_type(:uz), do: "Umowa zlecenie"
  defp format_contract_type(:uod), do: "Umowa o dzieło"

  defp format_contract_status(nil), do: "—"
  defp format_contract_status(:pending_signature), do: "Oczekuje na podpis"
  defp format_contract_status(:signed), do: "Podpisana"
  defp format_contract_status(:active), do: "Obowiązująca"

  defp present(nil), do: "—"
  defp present(""), do: "—"
  defp present(value), do: to_string(value)

  defp present_date(nil), do: "—"
  defp present_date(""), do: "—"
  defp present_date(%Date{} = date), do: TimeFormatter.format_date(date)
  defp present_date(date), do: to_string(date)

  defp payout_schedule(%{payout_day: day, payout_month_offset: 0}) when is_integer(day),
    do: gettext("Day %{day} of the same month", day: day)

  defp payout_schedule(%{payout_day: day, payout_month_offset: 1}) when is_integer(day),
    do: gettext("Day %{day} of the following month", day: day)

  defp payout_schedule(_contract), do: gettext("No information yet")

  defp assign_contract(socket, contract) do
    socket
    |> assign(:employment_contract, contract)
    |> assign(:contract_form, contract_form(contract, socket.assigns.scope))
  end

  defp contract_form(nil, _scope), do: nil

  defp contract_form(contract, scope) do
    contract
    |> AshPhoenix.Form.for_update(:update, domain: Payroll, scope: scope, as: "contract")
    |> to_form()
  end
end
