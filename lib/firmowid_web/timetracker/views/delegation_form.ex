defmodule FirmowidWeb.Timetracker.Views.DelegationForm do
  @moduledoc "Form for submitting a new business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.DesignSystem.Components.MonthPicker
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
      <.link
        kind="unstyled"
        navigate={~p"/ustawienia/profil"}
        class="absolute top-0 left-0.5 inline-flex items-center gap-2 text-sm"
      >
        <span class="flex size-6 items-center justify-center rounded-full bg-black text-white"><Lucideicons.chevron_left class="size-4" /></span>
        Wróć
      </.link>
      <main class="ml-32 max-w-366 pb-12">
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
          <div class="grid max-w-216 grid-cols-[auto_1fr] items-center gap-x-5 gap-y-4">
            <label class="text-grey-700 text-base" for="delegation_billing_month">
              Miesiąc rozliczeniowy
            </label>
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
            <span class="text-grey-700 text-base">Imię i nazwisko</span><span class="text-base text-black">{@current_user.name ||
              @current_user.email}</span>
            <span class="text-grey-700 text-base">Stanowisko</span><span class="text-base text-black">{@current_user.position ||
              "—"}</span>
            <label class="text-grey-700 text-base" for="delegation_start_date">Data wyjazdu</label>
            <div class="flex items-center gap-2">
              <.input
                id="delegation_start_date"
                name="delegation[start_date]"
                type="text"
                new
                value={nil}
                required
                placeholder="__.__.____"
                pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                input_class="placeholder:text-grey-300"
              />
              <span>-</span>
              <.input
                id="delegation_end_date"
                name="delegation[end_date]"
                type="text"
                new
                value={nil}
                required
                placeholder="__.__.____"
                pattern="[0-9]{2}\.[0-9]{2}\.[0-9]{4}"
                input_class="placeholder:text-grey-300"
              />
            </div>
            <label class="text-grey-700 text-base" for="delegation_purpose">Cel wyjazdu</label>
            <.input
              id="delegation_purpose"
              name="delegation[purpose]"
              type="text"
              new
              value={nil}
              required
              placeholder="np. Wyjazd na Elixir Conf"
              input_class="placeholder:text-grey-300"
            />
            <label class="text-grey-700 text-base" for="delegation_amount">Przewidywana kwota</label>
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
                input_class="w-25 text-right placeholder:text-grey-300"
              />
              <span>PLN</span>
            </div>
          </div>
          <p :if={@error} class="text-sm text-red-600">{@error}</p>
          <div class="mt-24 flex justify-end">
            <.button type="submit" variant="primary" accent="turquoise" size="big" class="w-54">Zaplanuj</.button>
          </div>
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
