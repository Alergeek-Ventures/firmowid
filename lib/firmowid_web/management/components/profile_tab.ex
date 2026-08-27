defmodule FirmowidWeb.Management.Components.ProfileTab do
  @moduledoc "LiveComponent for displaying employee profile information."
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Link
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
    user = assigns.user
    scope = assigns.scope

    {:ok, employment_contract} = Payroll.load_latest_contract(user.id, scope: scope)

    {:ok, salaries} =
      Payroll.list_salaries(%{user_id: user.id, active_at: Date.utc_today()}, scope: scope)

    salary = List.first(salaries)

    socket =
      socket
      |> assign(assigns)
      |> assign(:employment_contract, employment_contract)
      |> assign(:salary, salary)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col gap-6">
      <.card dimmed={@user.archived_at} class="pb-9">
        <.card_header>
          Dane korespondencyjne
        </.card_header>
        <div class="grid grid-cols-2 gap-5">
          <div class="flex flex-col gap-5">
            <.user_card_info label="Numer telefonu">
              {present(@user.phone)}
            </.user_card_info>
            <.user_card_info label="Adres e-mail">
              {present(@user.email)}
            </.user_card_info>
            <.user_card_info label="Slack">
              {present(@user.slack_id)}
            </.user_card_info>
          </div>
          <div class="flex flex-col gap-5">
            <.user_card_info label="Adres zamieszkania">
              {present(@user.residence_address)}
            </.user_card_info>

            <.user_card_info :if={@user.correspondence_address} label="Adres korespondencyjny">
              {@user.correspondence_address}
            </.user_card_info>
          </div>
        </div>
      </.card>

      <div class="flex h-fit flex-1 gap-6">
        <.card class="flex h-fit w-1/2 grow flex-col">
          <.card_header>
            Informacje o zatrudnieniu
          </.card_header>
          <div class="flex flex-col gap-4">
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
          </div>
        </.card>

        <.card class="flex h-fit w-1/2 shrink-0 flex-col">
          <.card_header>
            Kalendarz
          </.card_header>
          <p class="text-grey-500 text-sm">Wkrótce</p>
        </.card>
      </div>
    </div>
    """
  end

  defp format_contract_type(nil), do: "Nieokreślony"
  defp format_contract_type(:uop), do: "Umowa o pracę"
  defp format_contract_type(:b2b), do: "B2B"
  defp format_contract_type(:uz), do: "Umowa zlecenie"
  defp format_contract_type(:uod), do: "Umowa o dzieło"

  defp present(nil), do: "—"
  defp present(""), do: "—"
  defp present(value), do: to_string(value)

  defp present_date(nil), do: "—"
  defp present_date(""), do: "—"
  defp present_date(%Date{} = date), do: TimeFormatter.format_date(date)
  defp present_date(date), do: to_string(date)
end
