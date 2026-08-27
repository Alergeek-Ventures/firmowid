defmodule FirmowidWeb.Timetracker.Views.DelegationForm do
  @moduledoc "Form for submitting a new business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import FirmowidWeb.Timetracker.Components.Delegation
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Timetracker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    today = Date.utc_today()
    default_month = Date.beginning_of_month(today)
    months = billing_months(user.employment_date, today)

    {:ok,
     socket
     |> assign(:page_title, "Planowanie delegacji")
     |> assign(:months, months)
     |> assign(:default_month, default_month)
     |> assign(:billing_month, default_month)
     |> assign(:error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative mt-4 min-h-screen font-[340]">
      <.back_link
        kind="unstyled"
        navigate={~p"/ustawienia/profil"}
        class="absolute top-0 left-0.5 inline-flex text-sm"
      />
      <main class="px-32 pb-12">
        <h1 class="text-2xl/tight font-normal">Planowanie delegacji</h1>
        <p class="text-grey-700 mt-6 max-w-3xl text-base text-balance">
          Wypełnij poniższy wniosek. Po wysłaniu zostanie on przesłany do Twojego pracodawcy. Gdy zostanie zaakceptowany otrzymasz maila z potwierdzeniem.
        </p>
        <.form
          for={%{}}
          as={:delegation}
          id="delegation-form"
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
                    name="delegation[billing_month]"
                    value={Date.to_iso8601(@billing_month)}
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
                <div class="flex items-center gap-2">
                  <.input
                    id="delegation_start_date"
                    name="delegation[start_date]"
                    type="date"
                    new
                    value={nil}
                    required
                    placeholder="__.__.____"
                    pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                    aria-label="Data wyjazdu"
                    input_class="placeholder:text-grey-300 max-w-48"
                  />
                  <span aria-hidden="true">-</span>
                  <.input
                    id="delegation_end_date"
                    name="delegation[end_date]"
                    type="date"
                    new
                    value={nil}
                    required
                    placeholder="__.__.____"
                    pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                    aria-label="Data powrotu"
                    input_class="placeholder:text-grey-300 max-w-48"
                  />
                </div>
              </.form_row>
              <.form_row label="Cel wyjazdu" for="delegation_purpose">
                <.input
                  id="delegation_purpose"
                  name="delegation[purpose]"
                  type="text"
                  new
                  value={nil}
                  required
                  placeholder="np. Wyjazd na Elixir Conf"
                  input_class="placeholder:text-grey-300 max-w-125"
                />
              </.form_row>
              <.form_row label="Przewidywana kwota" for="delegation_amount">
                <div class="flex items-center gap-2">
                  <.input
                    id="delegation_amount"
                    name="delegation[advance_payment_amount]"
                    type="number"
                    new
                    value={nil}
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
          <p :if={@error} role="alert" class="text-sm text-red-600">{@error}</p>
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
    {:noreply, assign(socket, :billing_month, Date.from_iso8601!(month))}
  end

  @impl true
  def handle_event("save", %{"delegation" => params}, socket) do
    with {:ok, billing_month} <- Date.from_iso8601(params["billing_month"]),
         {:ok, start_date} <- parse_date(params["start_date"]),
         {:ok, end_date} <- parse_date(params["end_date"]),
         {:ok, amount} <- Decimal.cast(params["advance_payment_amount"]),
         true <- Date.compare(end_date, start_date) != :lt,
         {:ok, _delegation} <-
           Timetracker.create_delegation(
             %{
               title: params["purpose"],
               billing_month: billing_month,
               purpose: params["purpose"],
               advance_payment_amount: Money.new(:PLN, amount),
               start_date: start_date,
               end_date: end_date
             },
             scope: socket.assigns.ash_scope
           ) do
      {:noreply, push_navigate(socket, to: ~p"/ustawienia/konto")}
    else
      false ->
        {:noreply, assign(socket, :error, "Data zakończenia nie może być wcześniejsza niż data wyjazdu.")}

      _ ->
        {:noreply, assign(socket, :error, "Nie udało się zaplanować delegacji. Sprawdź dane formularza.")}
    end
  end

  defp billing_months(nil, today), do: billing_months(Date.beginning_of_month(today), today)

  defp billing_months(employment_date, today) do
    first = Date.beginning_of_month(employment_date)
    last = today |> Date.beginning_of_month() |> Date.add(32) |> Date.beginning_of_month()
    first |> Stream.iterate(&Date.add(&1, 1)) |> Enum.take_while(&(Date.compare(&1, last) != :gt))
  end

  defp parse_date(date) do
    with [day, month, year] <- String.split(date, "."),
         formatted_date = Enum.join([year, month, day], "-"),
         {:ok, parsed_date} <- Date.from_iso8601(formatted_date) do
      {:ok, parsed_date}
    else
      _ -> :error
    end
  end
end
