defmodule FirmowidWeb.Timetracker.Views.DelegationForm do
  @moduledoc "Form for submitting a new business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
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
     |> assign(:error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <.link
        kind="unstyled"
        navigate={~p"/ustawienia/konto"}
        class="m-3 inline-flex items-center gap-2"
      >
        <span class="flex size-7 items-center justify-center rounded-full bg-black text-white"><Lucideicons.chevron_left class="size-4" /></span>
        Wróć
      </.link>
      <main class="mx-auto max-w-4xl px-6 pb-12">
        <h1 class="text-2xl font-medium">Planowanie delegacji</h1>
        <p class="text-grey-700 mt-3 max-w-2xl text-balance">
          Wypełnij poniższy wniosek. Po wysłaniu zostanie on przesłany do Twojego pracodawcy. Gdy zostanie zaakceptowany otrzymasz maila z potwierdzeniem.
        </p>
        <.form
          for={%{}}
          as={:delegation}
          id="delegation-form"
          phx-submit="save"
          class="mt-10 space-y-5"
        >
          <div class="grid gap-2 sm:grid-cols-[max-content_minmax(0,1fr)] sm:items-center sm:gap-x-8">
            <label for="delegation_billing_month">Miesiąc rozliczeniowy</label>
            <select id="delegation_billing_month" name="delegation[billing_month]" class="input">
              <option
                :for={month <- @months}
                value={Date.to_iso8601(month)}
                selected={month == @default_month}
              >
                {Firmowid.Cldr.Date.to_string!(month, format: "MMMM y", locale: "pl")
                |> String.capitalize()}
              </option>
            </select>
            <span>Imię i nazwisko</span><span>{@current_user.name || @current_user.email}</span>
            <span>Stanowisko</span><span>{@current_user.position || "—"}</span>
            <label for="delegation_start_date">Data wyjazdu</label>
            <div class="flex items-center gap-2">
              <input
                id="delegation_start_date"
                name="delegation[start_date]"
                type="date"
                required
                class="input"
              />
              <span>-</span>
              <input name="delegation[end_date]" type="date" required class="input" />
            </div>
            <label for="delegation_purpose">Cel wyjazdu</label>
            <input
              id="delegation_purpose"
              name="delegation[purpose]"
              type="text"
              required
              placeholder="np. Wyjazd na Elixir Conf"
              class="input"
            />
            <label for="delegation_amount">Przewidywana kwota</label>
            <div class="flex items-center gap-2">
              <input
                id="delegation_amount"
                name="delegation[advance_payment_amount]"
                type="number"
                min="0"
                step="0.01"
                required
                class="input"
              /><span>PLN</span>
            </div>
          </div>
          <p :if={@error} class="text-sm text-red-600">{@error}</p>
          <div class="flex justify-end">
            <.button type="submit" variant="primary" accent="turquoise" size="big">Zaplanuj</.button>
          </div>
        </.form>
      </main>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"delegation" => params}, socket) do
    with {:ok, billing_month} <- Date.from_iso8601(params["billing_month"]),
         {:ok, start_date} <- Date.from_iso8601(params["start_date"]),
         {:ok, end_date} <- Date.from_iso8601(params["end_date"]),
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
end
