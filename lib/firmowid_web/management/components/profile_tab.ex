defmodule FirmowidWeb.Management.Components.ProfileTab do
  @moduledoc "LiveComponent for displaying employee profile information."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Link
  import FirmowidWeb.Management.Components.Card
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Payroll
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Payroll.Components.TaxProfileForm

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

    {:ok, salaries} =
      Payroll.list_salaries(%{user_id: user.id, active_at: Date.utc_today()}, scope: scope)

    salary = List.first(salaries)

    socket =
      socket
      |> assign_new(:editing_contract, fn -> false end)
      |> assign(:salary, salary)
      |> assign_new(:editing_tax_profile, fn -> false end)
      |> assign_contract(employment_contract)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col gap-6">
      <.card dimmed={@user.member.archived_at} class="pb-9">
        <.card_header>
          Dane korespondencyjne
        </.card_header>
        <div class="grid grid-cols-2 gap-5">
          <div class="flex flex-col gap-5">
            <.field_row label="Numer telefonu">
              {present(@user.member.phone)}
            </.field_row>
            <.field_row label="Adres e-mail">
              {present(@user.email)}
            </.field_row>
            <.field_row label="Slack">
              {present(@user.member.slack_url) |> String.replace_prefix("https://", "")}
            </.field_row>
          </div>
          <div class="flex flex-col gap-5">
            <.field_row label="Adres zamieszkania">
              {present(@user.member.residence_address)}
            </.field_row>

            <.field_row :if={@user.member.correspondence_address} label="Adres korespondencyjny">
              {@user.member.correspondence_address}
            </.field_row>
          </div>
        </div>
      </.card>

      <div class="flex h-fit flex-1 gap-6">
        <.card class="flex h-fit w-1/2 grow flex-col">
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
                <.field_row label="Status" for={@contract_form[:status].id}>
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
                </.field_row>
                <.field_row label="Rodzaj umowy" for={@contract_form[:contract_type].id}>
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
                </.field_row>
                <.field_row label="Stanowisko" for={@contract_form[:position].id}>
                  <.input field={@contract_form[:position]} class="w-full" />
                </.field_row>
                <.field_row label="Data podpisania umowy" for={@contract_form[:signed_at].id}>
                  <.input field={@contract_form[:signed_at]} type="date" class="w-full" />
                </.field_row>
              <% else %>
                <.field_row label="Status umowy">
                  {format_contract_status(@employment_contract && @employment_contract.status)}
                </.field_row>
                <.field_row label="Rodzaj umowy">
                  {format_contract_type(@employment_contract && @employment_contract.contract_type)}
                </.field_row>
                <.field_row label="Stanowisko">
                  {present(@employment_contract && @employment_contract.position)}
                </.field_row>
                <.field_row label="Data podpisania umowy">
                  <div class="flex items-center gap-2">
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
                  </div>
                </.field_row>
              <% end %>
            </div>
          </.form>
        </.card>

        <div class="flex w-1/2 shrink-0 flex-col gap-6">
          <.card :if={@tax_profile_fields != []} class="flex h-fit flex-col">
            <.card_header>
              {gettext("Net forecast assumptions")}
              <:actions>
                <.card_edit_actions
                  editing={@editing_tax_profile}
                  form="tax-profile-form"
                  toggle_event="toggle_tax_profile_editor"
                  target={@myself}
                  edit_label={gettext("Edit net forecast assumptions")}
                />
              </:actions>
            </.card_header>
            <.form
              id="tax-profile-form"
              for={@tax_profile_form}
              phx-target={@myself}
              phx-change="validate_tax_profile"
              phx-submit="save_tax_profile"
            >
              <div class="flex flex-col gap-4">
                <%= if @editing_tax_profile do %>
                  <.field_row
                    :for={field <- @tax_profile_fields}
                    label={TaxProfileForm.field_label(field)}
                    for={TaxProfileForm.input_id(@tax_profile_form, field)}
                  >
                    <TaxProfileForm.select form={@tax_profile_form} field={field} />
                  </.field_row>
                <% else %>
                  <.field_row
                    :for={field <- @tax_profile_fields}
                    label={TaxProfileForm.field_label(field)}
                  >
                    <TaxProfileForm.saved_value form={@tax_profile_form} field={field} />
                  </.field_row>
                <% end %>
              </div>
            </.form>
            <p class="text-xs/snug text-grey-600">{TaxProfileForm.notice()}</p>
          </.card>

          <.card class="flex h-fit flex-col">
            <.card_header>
              Kalendarz
            </.card_header>
            <p class="text-sm text-grey-500">Wkrótce</p>
          </.card>
        </div>
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

  def handle_event("toggle_tax_profile_editor", _params, socket) do
    {:noreply,
     socket
     |> update(:editing_tax_profile, &(!&1))
     |> assign(
       :tax_profile_form,
       TaxProfileForm.form(socket.assigns.user.member, socket.assigns.scope)
     )}
  end

  def handle_event("validate_tax_profile", %{"member" => params}, socket) do
    form =
      socket.assigns.tax_profile_form
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :tax_profile_form, form)}
  end

  def handle_event("save_tax_profile", %{"member" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.tax_profile_form, params: params) do
      {:ok, member} ->
        user = %{socket.assigns.user | member: member}
        # The employee view passes its user to every tab, so it must not keep the old profile.
        send(self(), {:employee_updated, user})

        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:editing_tax_profile, false)
         |> assign(:tax_profile_form, TaxProfileForm.form(member, socket.assigns.scope))}

      {:error, form} ->
        {:noreply, assign(socket, :tax_profile_form, form)}
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

  # The assumptions shown depend on the contract type, so their form is rebuilt
  # from the saved profile with the contract, dropping unsaved assumption edits.
  defp assign_contract(socket, contract) do
    %{user: user, scope: scope} = socket.assigns

    socket
    |> assign(:employment_contract, contract)
    |> assign(:contract_form, contract_form(contract, scope))
    |> assign(:tax_profile_fields, TaxProfileForm.fields(contract && contract.contract_type))
    |> assign(:tax_profile_form, TaxProfileForm.form(user.member, scope))
  end

  defp contract_form(nil, _scope), do: nil

  defp contract_form(contract, scope) do
    contract
    |> AshPhoenix.Form.for_update(:update, domain: Payroll, scope: scope, as: "contract")
    |> to_form()
  end
end
