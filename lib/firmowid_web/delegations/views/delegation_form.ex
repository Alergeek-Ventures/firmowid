defmodule FirmowidWeb.Delegations.Views.DelegationForm do
  @moduledoc "Form for submitting a new business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Delegations.Delegation

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    today = Date.utc_today()
    default_month = Date.beginning_of_month(today)
    months = billing_months(user.employment_date, today)
    form = delegation_form(socket.assigns.ash_scope, default_month)

    {:ok,
     socket
     |> assign(:page_title, "Planowanie delegacji")
     |> assign(:months, months)
     |> assign(:default_month, default_month)
     |> assign(:billing_month, default_month)
     |> assign(:transport_types, [""])
     |> assign(:form, form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative mt-4 min-h-screen font-[340]">
      <.back
        navigate={~p"/ustawienia/profil"}
        class="absolute top-0 left-0.5 inline-flex text-sm"
      />
      <main class="px-32 pb-12">
        <h1 class="text-2xl/tight font-normal">Planowanie delegacji</h1>
        <p class="text-grey-700 mt-6 max-w-3xl text-base text-balance">
          Wypełnij poniższy wniosek. Po wysłaniu zostanie on przesłany do Twojego pracodawcy. Gdy zostanie zaakceptowany otrzymasz maila z potwierdzeniem.
        </p>
        <.form
          for={@form}
          id="delegation-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-19"
        >
          <fieldset class="contents">
            <legend class="sr-only">Dane delegacji</legend>
            <div class="grid max-w-216 grid-cols-[auto_1fr] items-center gap-x-5 gap-y-4">
              <.form_row label="Miesiąc rozliczeniowy" for="delegation_billing_month">
                <div class="relative w-57">
                  <.month_picker
                    id="delegation_billing_month"
                    selected_date={Date.to_iso8601(@billing_month)}
                    active_months={@months}
                    variant="outline"
                    size="small"
                    class="bg-grey-50 w-full pr-10"
                  />
                  <Lucideicons.chevron_down class="text-grey-700 pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2" />
                  <input
                    type="hidden"
                    name={@form[:billing_month].name}
                    value={@form[:billing_month].value}
                  />
                </div>
              </.form_row>
              <dl class="contents">
                <.detail_row dd_class="mt-8" dt_class="mt-8" label="Imię i nazwisko">
                  {@current_user.name || @current_user.email}
                </.detail_row>
                <.detail_row label="Stanowisko">{@current_user.position || "—"}</.detail_row>
              </dl>
              <.form_row label="Data wyjazdu" for="delegation_start_date">
                <div class="flex items-start gap-2">
                  <.input
                    field={@form[:start_date]}
                    id="delegation_start_date"
                    type="date"
                    new
                    required
                    placeholder="__.__.____"
                    pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                    aria-label="Data wyjazdu"
                    input_class="placeholder:text-grey-300 max-w-48"
                  />
                  <span aria-hidden="true" class="mt-2">-</span>
                  <.input
                    field={@form[:end_date]}
                    id="delegation_end_date"
                    type="date"
                    new
                    required
                    placeholder="__.__.____"
                    pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                    aria-label="Data powrotu"
                    input_class="placeholder:text-grey-300 max-w-48"
                  />
                </div>
              </.form_row>
              <.form_row
                label="Miejsce podróży"
                for="delegation_destination"
                label_class="self-start pt-2"
              >
                <.input
                  field={@form[:destination]}
                  id="delegation_destination"
                  type="text"
                  new
                  required
                  input_class="max-w-125"
                />
              </.form_row>
              <.form_row
                label="Środek lokomocji"
                for="delegation_transport_types_0"
                label_class="self-start pt-2"
              >
                <div class="flex w-125 flex-col gap-2">
                  <div
                    :for={{transport_type, index} <- Enum.with_index(@transport_types)}
                    class="flex gap-2"
                  >
                    <.input
                      id={"delegation_transport_types_#{index}"}
                      name={@form[:transport_types].name <> "[]"}
                      value={transport_type}
                      type="select"
                      new
                      required
                      prompt="Wybierz z listy"
                      options={transport_options()}
                      input_class="w-28 invalid:text-grey-300"
                    />
                    <.button
                      :if={index < length(@transport_types) - 1}
                      type="button"
                      variant="unstyled"
                      phx-click="remove_transport_type"
                      phx-value-index={index}
                      class="text-grey-500 inline-flex size-8 items-center justify-center transition-colors hover:text-red-700"
                      aria-label="Usuń środek lokomocji"
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
                      + Dodaj kolejny
                    </.button>
                  </div>
                </div>
              </.form_row>
              <.form_row label="Cel wyjazdu" for="delegation_purpose">
                <.input
                  field={@form[:purpose]}
                  id="delegation_purpose"
                  type="text"
                  new
                  required
                  placeholder="np. Wyjazd na Elixir Conf"
                  input_class="placeholder:text-grey-300 max-w-125"
                />
              </.form_row>
              <.form_row label="Przewidywana kwota" for="delegation_amount">
                <div class="flex items-center gap-2">
                  <.input
                    field={@form[:advance_payment_amount]}
                    id="delegation_amount"
                    type="number"
                    new
                    min="0"
                    step="0.01"
                    required
                    placeholder="0.00"
                    aria-describedby="delegation_amount_currency"
                    input_class="w-25 text-right placeholder:text-grey-300 max-w-25"
                  />
                  <span id="delegation_amount_currency" class="text-grey-500 text-sm">PLN</span>
                </div>
              </.form_row>
            </div>
          </fieldset>
          <.button
            type="submit"
            variant="primary"
            accent="turquoise"
            class="float-end mt-20 mr-4 w-42"
          >Zaplanuj</.button>
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
        {:noreply, socket |> assign(:billing_month, billing_month) |> assign(:form, form)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, "Wybierz poprawny miesiąc rozliczeniowy.")}
    end
  end

  @impl true
  def handle_event("validate", %{"delegation" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply,
     socket
     |> assign(:form, form)
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

  defp billing_months(nil, today), do: billing_months(Date.beginning_of_month(today), today)

  defp billing_months(employment_date, today) do
    first = Date.beginning_of_month(employment_date)
    last = today |> Date.beginning_of_month() |> Date.add(32) |> Date.beginning_of_month()
    first |> Stream.iterate(&Date.add(&1, 1)) |> Enum.take_while(&(Date.compare(&1, last) != :gt))
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
      {"Kolej", "railway"},
      {"Samolot", "airplane"},
      {"Autobus", "bus"},
      {"Inne", "other"}
    ]
  end
end
