defmodule FirmowidWeb.Delegations.Views.DelegationForm do
  @moduledoc "Form for submitting a new business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Delegations.Delegation
  alias Firmowid.Payroll

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    user = %{
      user
      | member: Ash.load!(user.member, :display_name, scope: socket.assigns.ash_scope)
    }

    today = Date.utc_today()
    default_month = Date.beginning_of_month(today)
    form = delegation_form(socket.assigns.ash_scope, default_month)

    {:ok, employment_contract} =
      Payroll.load_current_contract(user.member.id, scope: socket.assigns.ash_scope)

    months = billing_months(employment_contract && employment_contract.starts_at, today)

    {:ok,
     socket
     |> assign(:current_user, user)
     |> assign(:page_title, gettext("Business trip planning"))
     |> assign(:months, months)
     |> assign(:default_month, default_month)
     |> assign(:billing_month, default_month)
     |> assign(:billing_month_chosen?, false)
     |> assign(:transport_types, [""])
     |> assign(:employment_contract, employment_contract)
     |> assign(:form, form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-4 min-h-screen font-[340]">
      <div class="mb-6">
        <.back navigate={~p"/ustawienia/profil"} class="inline-flex text-sm" />
      </div>
      <main class="px-0 pb-12 sm:px-32">
        <h1 class="text-2xl/tight font-normal">{gettext("Business trip planning")}</h1>
        <p class="mt-6 max-w-3xl text-base text-balance text-grey-700">
          {gettext(
            "Fill in the request below. After you send it, it will be forwarded to your employer. Once it is approved, you will receive a confirmation email."
          )}
        </p>
        <.form
          for={@form}
          id="delegation-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-10 sm:mt-19"
        >
          <fieldset class="contents">
            <legend class="sr-only">{gettext("Business trip details")}</legend>
            <div class="grid max-w-216 grid-cols-1 gap-y-2 sm:grid-cols-[auto_1fr] sm:items-center sm:gap-x-5 sm:gap-y-4">
              <.form_row label={gettext("Billing month")} for="delegation_billing_month">
                <div class="relative w-57">
                  <.month_picker
                    id="delegation_billing_month"
                    selected_date={Date.to_iso8601(@billing_month)}
                    active_months={@months}
                    show_on_mobile
                    variant="outline"
                    size="small"
                    class="w-full bg-grey-50 pr-10"
                  />
                  <Lucideicons.chevron_down class="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-grey-700" />
                  <input
                    type="hidden"
                    name={@form[:billing_month].name}
                    value={@form[:billing_month].value}
                  />
                </div>
              </.form_row>
              <dl class="contents">
                <.detail_row dd_class="sm:mt-8" dt_class="sm:mt-8" label={gettext("Full name")}>
                  {@current_user.member.display_name}
                </.detail_row>
                <.detail_row label={gettext("Position")}>
                  {(@employment_contract && @employment_contract.position) || "—"}
                </.detail_row>
              </dl>
              <.form_row label={gettext("Departure date")} for="delegation_start_date">
                <div class="flex flex-wrap items-start gap-2">
                  <div class="w-full sm:w-auto">
                    <span class="text-sm text-grey-700 sm:hidden">{pgettext(
                      "date range start",
                      "from"
                    )}</span>
                    <.input
                      field={@form[:start_date]}
                      id="delegation_start_date"
                      type="date"
                      required
                      placeholder="__.__.____"
                      pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                      aria-label={gettext("Departure date")}
                      input_class="placeholder:text-grey-300 w-full sm:max-w-48"
                    />
                  </div>
                  <span aria-hidden="true" class="mt-2 hidden sm:block">-</span>
                  <div class="w-full sm:w-auto">
                    <span class="text-sm text-grey-700 sm:hidden">{pgettext("date range end", "to")}</span>
                    <.input
                      field={@form[:end_date]}
                      id="delegation_end_date"
                      type="date"
                      required
                      placeholder="__.__.____"
                      pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                      aria-label={gettext("Return date")}
                      input_class="placeholder:text-grey-300 w-full sm:max-w-48"
                    />
                  </div>
                </div>
              </.form_row>
              <.form_row
                label={gettext("Destination")}
                for="delegation_destination"
                label_class="self-start pt-2"
              >
                <.input
                  field={@form[:destination]}
                  id="delegation_destination"
                  type="text"
                  required
                  input_class="w-full sm:max-w-125"
                />
              </.form_row>
              <.form_row
                label={gettext("Means of transport")}
                for="delegation_transport_types_0"
                label_class="self-start pt-2"
              >
                <div class="flex w-full flex-col gap-2 sm:w-125">
                  <div
                    :for={{transport_type, index} <- Enum.with_index(@transport_types)}
                    class="flex flex-wrap gap-2"
                  >
                    <.input
                      id={"delegation_transport_types_#{index}"}
                      name={@form[:transport_types].name <> "[]"}
                      value={transport_type}
                      type="select"
                      required
                      prompt={gettext("Choose from the list")}
                      options={transport_options()}
                      selected_labels={%{"bus" => pgettext("means of transport", "Bus")}}
                      container_class="w-full sm:w-56"
                    />
                    <.button
                      :if={index < length(@transport_types) - 1}
                      type="button"
                      variant="unstyled"
                      phx-click="remove_transport_type"
                      phx-value-index={index}
                      class="inline-flex size-8 items-center justify-center text-grey-500 transition-colors hover:text-brick-700"
                      aria-label={gettext("Remove means of transport")}
                    >
                      <Lucideicons.x class="size-4" />
                    </.button>
                    <.button
                      :if={index == length(@transport_types) - 1}
                      type="button"
                      variant="secondary"
                      size="small"
                      phx-click="add_transport_type"
                    >
                      {gettext("+ Add another")}
                    </.button>
                  </div>
                </div>
              </.form_row>
              <.form_row label={gettext("Purpose of the trip")} for="delegation_purpose">
                <.input
                  field={@form[:purpose]}
                  id="delegation_purpose"
                  type="text"
                  required
                  placeholder={gettext("e.g. A trip to Elixir Conf")}
                  input_class="placeholder:text-grey-300 w-full sm:max-w-125"
                />
              </.form_row>
              <.form_row label={gettext("Estimated amount")} for="delegation_amount">
                <div class="flex flex-wrap items-center gap-2">
                  <div class="min-w-0 flex-1 sm:flex-none">
                    <.input
                      field={@form[:expected_cost]}
                      id="delegation_amount"
                      type="number"
                      min="0"
                      step="0.01"
                      required
                      placeholder="0,00"
                      aria-describedby="delegation_amount_currency"
                      input_class="w-full text-right placeholder:text-grey-300 sm:w-25"
                    />
                  </div>
                  <span id="delegation_amount_currency" class="text-sm text-grey-500">PLN</span>
                </div>
              </.form_row>
            </div>
          </fieldset>
          <.button
            type="submit"
            variant="primary"
            accent="teal"
            class="mt-20 w-full sm:float-end sm:mr-4 sm:w-42"
          >{pgettext("business trip form", "Plan")}</.button>
        </.form>
      </main>
    </div>
    """
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(Map.put(AshPhoenix.Form.params(socket.assigns.form.source), "billing_month", month))
      |> to_form()

    case Date.from_iso8601(month) do
      {:ok, billing_month} ->
        {:noreply,
         socket
         |> assign(:billing_month, billing_month)
         |> assign(:billing_month_chosen?, true)
         |> assign(:form, form)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, gettext("Choose a valid billing month."))}
    end
  end

  @impl true
  def handle_event("validate", %{"delegation" => params}, socket) do
    {params, billing_month} = follow_trip_month(params, socket.assigns)

    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:billing_month, billing_month)
     |> assign(:transport_types, transport_types(params))}
  end

  def handle_event("add_transport_type", _params, socket) do
    {:noreply, update(socket, :transport_types, &(&1 ++ [""]))}
  end

  def handle_event("remove_transport_type", %{"index" => index}, socket) do
    {index, ""} = Integer.parse(index)

    {:noreply, update(socket, :transport_types, &List.delete_at(&1, index))}
  end

  def handle_event("save", %{"delegation" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _delegation} ->
        {:noreply, push_navigate(socket, to: ~p"/ustawienia/profil")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  # Until the employee picks the billing month, it follows the month of departure,
  # as long as that month can be picked.
  defp follow_trip_month(params, %{billing_month_chosen?: true} = assigns), do: {params, assigns.billing_month}

  defp follow_trip_month(params, assigns) do
    case trip_month(params["start_date"], assigns.months) do
      nil -> {params, assigns.billing_month}
      month -> {Map.put(params, "billing_month", Date.to_iso8601(month)), month}
    end
  end

  defp trip_month(start_date, months) do
    case Date.from_iso8601(start_date) do
      {:ok, date} -> Enum.find(months, &(&1 == Date.beginning_of_month(date)))
      {:error, _reason} -> nil
    end
  end

  defp billing_months(nil, today), do: billing_months(Date.beginning_of_month(today), today)

  # Months from the start of the contract up to a year ahead, so trips planned well in
  # advance can be billed in the month of departure.
  defp billing_months(starts_at, today) do
    first = Date.beginning_of_month(starts_at)
    last = today |> Date.beginning_of_month() |> Date.shift(month: 12)

    first
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, last) != :gt))
  end

  defp delegation_form(scope, billing_month) do
    Delegation
    |> AshPhoenix.Form.for_create(:create,
      scope: scope,
      as: "delegation",
      params: %{"billing_month" => Date.to_iso8601(billing_month)},
      transform_params: fn params, _type -> Map.put(params, "title", params["purpose"]) end
    )
    |> to_form()
  end

  defp transport_types(%{"transport_types" => transport_types}) when is_list(transport_types), do: transport_types

  defp transport_types(_params), do: [""]

  defp transport_options do
    [
      {pgettext("means of transport", "Train"), "railway"},
      {pgettext("means of transport", "Airplane"), "airplane"},
      {pgettext("means of transport", "Bus (excluding public transport)"), "bus"},
      {pgettext("means of transport", "Public transport"), "public_transport"},
      {pgettext("means of transport", "Other"), "other"}
    ]
  end
end
