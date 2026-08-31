defmodule FirmowidWeb.Delegations.Views.Delegation do
  @moduledoc "Settlement page for an approved business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]

  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationExpenseExtractor

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load_delegation(id, socket) do
      {:ok, nil} ->
        {:ok, push_navigate(socket, to: ~p"/ustawienia/profil")}

      {:ok, delegation} ->
        if delegation.status in [:in_progress, :complete] do
          {:ok, setup_socket(socket, delegation)}
        else
          {:ok, push_navigate(socket, to: ~p"/ustawienia/profil")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative mt-4">
      <.back
        navigate={~p"/ustawienia/profil"}
        class="absolute top-0 left-0.5 inline-flex text-sm"
      />
      <main class="grid gap-10 px-32 pr-34 pb-12 font-[340] lg:grid-cols-[auto_22.5rem]">
        <section aria-labelledby="delegation-settlement-title">
          <small class="text-grey-500 text-sm">Cel:
          <span class="text-grey-700">{@delegation.purpose}</span></small>
          <h1 id="delegation-settlement-title" class="mt-1 text-2xl font-medium">
            Rozliczenie delegacji
          </h1>
          <p class="text-grey-700 mt-3 max-w-2xl text-balance">
            Załącz bilety i rachunki. Uzupełnij potrzebne dane. Kwoty i numery faktur uzupełnimy automatycznie.
          </p>

          <.expense_section
            title="Przejazdy"
            expenses={@delegation.transport_expenses}
            upload={Map.get(@uploads, :transport)}
            kind="transport"
            editable?={@editable?}
            sort_active?={@sort_active?}
            description_visible?={@description_visible?}
            timezone={@timezone}
          >
            <:icon><Lucideicons.plane class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title="Nocleg"
            expenses={@delegation.accommodation_expenses}
            upload={Map.get(@uploads, :accommodation)}
            kind="accommodation"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            timezone={@timezone}
          >
            <:icon><Lucideicons.bed_double class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title="Inne wydatki"
            expenses={@delegation.other_expenses}
            upload={Map.get(@uploads, :other)}
            kind="other"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            timezone={@timezone}
          >
            <:icon><Lucideicons.wallet class="size-5" /></:icon>
          </.expense_section>
        </section>
        <aside class="lg:pt-1">
          <dl class="text-grey-500 flex justify-end gap-4">
            <small>
              <dt class="inline">Termin:</dt>
              <dd class="text-grey-700 inline tabular-nums">
                <.date_range start_date={@delegation.start_date} end_date={@delegation.end_date} />
              </dd>
            </small>
            <small>
              <dt class="inline">Zaliczka:</dt>
              <dd class="text-grey-700 inline">
                {Money.to_string!(@delegation.advance_payment_amount)}
              </dd>
            </small>
          </dl>
          <div class="mt-6 rounded-lg bg-white px-6 py-4 shadow-sm lg:mt-47">
            <h2 class="text-grey-500 font-normal">Podsumowanie</h2>
            <dl class="mt-6 space-y-3 text-sm">
              <.summary_row label="Przejazdy" value={sum(@delegation.transport_expenses)} />
              <.summary_row label="Nocleg" value={sum(@delegation.accommodation_expenses)} />
              <.summary_row label="Inne" value={sum(@delegation.other_expenses)} />
              <div class="border-grey-100 my-5 space-y-3 border-y py-5">
                <.summary_row label="Razem koszty" value={@total} class="font-medium" />
                <.summary_row
                  label="Pobrana zaliczka"
                  value={@delegation.advance_payment_amount}
                />
              </div>
              <.summary_row label={@balance_label} value={@balance} />
            </dl>
          </div>
          <.button
            :if={@editable?}
            variant="primary"
            accent="turquoise"
            size="big"
            class="mt-6 w-full"
            phx-click="submit"
          >Wyślij</.button>
        </aside>
      </main>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :icon, required: true
  attr :expenses, :list, required: true
  attr :upload, :any, required: true
  attr :kind, :string, required: true
  attr :editable?, :boolean, required: true
  attr :sort_active?, :boolean, required: true
  attr :description_visible?, :map, default: %{}
  attr :timezone, :string, required: true

  defp expense_section(assigns) do
    ~H"""
    <section class="mt-10">
      <header class="mb-3 flex items-center justify-between">
        <h2 class="flex items-center gap-2 font-normal">
          {render_slot(@icon)}{@title}
        </h2>
        <.button
          :if={@kind == "transport"}
          type="button"
          variant="ghost"
          size="small"
          disabled={
            @expenses == [] or
              (length(@expenses) > 0 and Enum.any?(@expenses, &(length(&1.trips || []) > 1)))
          }
          phx-click="sort"
        >Sortuj chronologicznie <Lucideicons.arrow_down_up class="size-4" /></.button>
      </header>
      <div class="space-y-3">
        <article :for={expense <- @expenses} class="border-grey-200 rounded-lg border p-4">
          <div class="text-grey-500 flex items-center justify-between gap-3 text-sm">
            <span class="flex min-w-0 items-center gap-2 truncate"><.icon
              name="hero-document"
              class="size-5 shrink-0"
            />{expense.original_filename}</span>
            <.button
              :if={@editable?}
              type="button"
              variant="icon"
              aria-label="Usuń dokument"
              phx-click="delete"
              phx-value-kind={@kind}
              phx-value-id={expense.id}
            ><Lucideicons.x class="size-4" /></.button>
          </div>
          <form
            :if={@editable?}
            id={"#{@kind}-expense-#{expense.id}"}
            phx-change="update"
            phx-value-kind={@kind}
            phx-value-id={expense.id}
            class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
          >
            <.input
              :if={@kind == "transport"}
              id={"#{@kind}-transport-type-#{expense.id}"}
              name="transport_type"
              value={expense.transport_type}
              type="select"
              new
              label="Środek lokomocji"
              options={transport_options()}
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-locality-#{expense.id}"}
              name="locality"
              value={expense.locality}
              type="text"
              new
              label="Miejscowość"
            />
            <.document_fields expense={expense} />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-arrival-date-#{expense.id}"}
              name="arrival_date"
              value={expense.arrival_date}
              type="date"
              new
              label="Zameldowanie"
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-departure-date-#{expense.id}"}
              name="departure_date"
              value={expense.departure_date}
              type="date"
              new
              label="Wymeldowanie"
            />
            <.expense_description
              :if={@kind == "accommodation"}
              expense={expense}
              kind={@kind}
              visible?={Map.get(@description_visible?, expense.id, false)}
            />
            <.input
              :if={@kind == "other"}
              id={"#{@kind}-description-#{expense.id}"}
              name="description"
              value={expense.description}
              type="textarea"
              new
              label="Opis"
              class="col-span-full"
            />
          </form>
          <.trip_fields
            :if={@kind == "transport"}
            trips={expense.trips || []}
            editable?={@editable?}
            timezone={@timezone}
            description_visible?={@description_visible?}
          />
        </article>
        <.pending_expense
          :for={entry <- if(@upload, do: @upload.entries, else: [])}
          entry={entry}
          kind={@kind}
        />
        <form
          :if={@editable? && @upload}
          id={"#{@kind}-upload-form"}
          phx-change="upload"
          phx-submit="upload"
          class="relative"
        >
          <.file_upload
            upload={@upload}
            prompt="Przeciągnij tu fakturę/rachunek lub wybierz plik z komputera"
            content_class="text-grey-700!"
            class="border-grey-200! justify-between! rounded-lg! border! px-4! py-7!"
          />
          <.button
            as="label"
            for={@upload.ref}
            type="button"
            variant="secondary"
            size="small"
            class="absolute top-1/2 right-3 -translate-y-1/2"
          >Wybierz plik</.button>
        </form>
      </div>
    </section>
    """
  end

  attr :expense, :any, required: true

  defp document_fields(assigns) do
    ~H"""
    <.input
      id={"document-number-#{@expense.id}"}
      name="document_number"
      value={@expense.document_number}
      type="text"
      new
      label="Nr dokumentu"
    />
    <div class="flex items-end gap-2">
      <div class="min-w-0 flex-1">
        <.input
          id={"expense-amount-#{@expense.id}"}
          name="expense_amount"
          value={Money.to_decimal(@expense.expense_amount)}
          type="number"
          new
          min="0"
          step="0.01"
          label="Kwota"
          aria-describedby={"expense-amount-currency-#{@expense.id}"}
        />
      </div>
      <span
        id={"expense-amount-currency-#{@expense.id}"}
        class="text-grey-500 shrink-0 pb-2 text-sm whitespace-nowrap"
      >
        PLN
      </span>
    </div>
    """
  end

  attr :trips, :list, required: true
  attr :editable?, :boolean, required: true
  attr :timezone, :string, required: true
  attr :description_visible?, :map, required: true

  defp trip_fields(assigns) do
    ~H"""
    <section :for={trip <- @trips} class="border-grey-100 mt-4 border-t pt-4">
      <form
        :if={@editable?}
        id={"transport-trip-#{trip.id}"}
        phx-change="update-trip"
        phx-value-id={trip.id}
      >
        <table class="border-separate border-spacing-y-3 text-left text-sm">
          <thead class="text-grey-500">
            <tr>
              <th scope="col"></th>
              <th scope="col" class="font-normal">Miejscowość</th>
              <th scope="col" class="font-normal">Data</th>
              <th scope="col" class="font-normal">Godzina</th>
              <th scope="col"></th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <th scope="row" class="text-grey-700 pr-3 font-normal">Wyjazd</th>
              <td class="pr-3">
                <.input
                  id={"trip-departure-city-#{trip.id}"}
                  name="departure_city"
                  value={trip.departure_city}
                  type="text"
                  new
                  aria-label="Miejscowość wyjazdu"
                  input_class="w-36"
                />
              </td>
              <td class="pr-3">
                <.input
                  id={"trip-departure-date-#{trip.id}"}
                  name="departure_date"
                  value={date_value(trip.departure_datetime, @timezone)}
                  type="date"
                  new
                  aria-label="Data wyjazdu"
                  input_class="w-34"
                />
              </td>
              <td>
                <.input
                  id={"trip-departure-time-#{trip.id}"}
                  name="departure_time"
                  value={time_value(trip.departure_datetime, @timezone)}
                  type="time"
                  new
                  aria-label="Godzina wyjazdu"
                  input_class="w-24"
                />
              </td>
              <td rowspan="2" class="pl-3 align-bottom">
                <.button
                  type="button"
                  variant="unstyled"
                  class={[
                    "block text-sm whitespace-nowrap",
                    Map.get(@description_visible?, trip.id, false) && "text-red-700"
                  ]}
                  phx-click="toggle-description"
                  phx-value-id={trip.id}
                >{if Map.get(@description_visible?, trip.id, false),
                  do: "Usuń opis",
                  else: "Dodaj opis"}</.button>
              </td>
            </tr>
            <tr>
              <th scope="row" class="text-grey-700 pr-3 font-normal">Przyjazd</th>
              <td class="pr-3">
                <.input
                  id={"trip-arrival-city-#{trip.id}"}
                  name="arrival_city"
                  value={trip.arrival_city}
                  type="text"
                  new
                  aria-label="Miejscowość przyjazdu"
                  input_class="w-36"
                />
              </td>
              <td class="pr-3">
                <.input
                  id={"trip-arrival-date-#{trip.id}"}
                  name="arrival_date"
                  value={date_value(trip.arrival_datetime, @timezone)}
                  type="date"
                  new
                  aria-label="Data przyjazdu"
                  input_class="w-34"
                />
              </td>
              <td>
                <.input
                  id={"trip-arrival-time-#{trip.id}"}
                  name="arrival_time"
                  value={time_value(trip.arrival_datetime, @timezone)}
                  type="time"
                  new
                  aria-label="Godzina przyjazdu"
                  input_class="w-24"
                />
              </td>
            </tr>
          </tbody>
        </table>
        <.input
          :if={Map.get(@description_visible?, trip.id, false)}
          id={"trip-description-#{trip.id}"}
          name="description"
          value={trip.description}
          type="textarea"
          new
          label="Opis"
        />
      </form>
    </section>
    """
  end

  attr :expense, :any, required: true
  attr :kind, :string, required: true
  attr :visible?, :boolean, required: true

  defp expense_description(assigns) do
    ~H"""
    <div class="col-span-full flex flex-col items-end gap-2">
      <.input
        :if={@visible?}
        id={"#{@kind}-description-#{@expense.id}"}
        name="description"
        value={@expense.description}
        type="textarea"
        new
        label="Opis"
        class="w-full"
      />
      <.button
        type="button"
        variant="unstyled"
        class={["text-sm", @visible? && "text-red-700"]}
        phx-click="toggle-description"
        phx-value-id={@expense.id}
      >{if @visible?, do: "Usuń opis", else: "Dodaj opis"}</.button>
    </div>
    """
  end

  attr :entry, :any, required: true
  attr :kind, :string, required: true

  defp pending_expense(assigns) do
    ~H"""
    <article
      :if={!@entry.done?}
      id={"#{@kind}-pending-expense-#{@entry.ref}"}
      aria-busy="true"
      class="border-grey-200 rounded-lg border p-4"
    >
      <div class="text-grey-500 flex items-center justify-between gap-3 text-sm">
        <span class="flex min-w-0 items-center gap-2 truncate">
          <Lucideicons.loader_circle class="size-5 shrink-0 animate-spin" />
          {@entry.client_name}
        </span>
        <span class="shrink-0 tabular-nums">{@entry.progress}%</span>
      </div>
      <div class="bg-grey-100 mt-4 h-9 animate-pulse rounded" />
      <div class="bg-grey-100 mt-3 h-9 animate-pulse rounded" />
    </article>
    """
  end

  attr :label, :string, required: true
  attr :value, Money, required: true
  attr :class, :string, default: ""

  defp summary_row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @class]}>
      <dt>{@label}</dt><dd class={[Money.zero?(@value) && "text-grey-500"]}>
        {Money.to_string!(@value)}
      </dd>
    </div>
    """
  end

  @impl true
  def handle_event("upload", _params, socket), do: {:noreply, socket}

  def handle_event("update", %{"kind" => kind, "id" => id} = params, socket) do
    attrs = update_attrs(kind, params)
    result = update_expense(kind, id, attrs, socket.assigns.ash_scope)

    {:noreply,
     if(match?({:ok, _}, result),
       do: reload(socket),
       else: put_flash(socket, :error, "Nie udało się zapisać danych.")
     )}
  end

  def handle_event("update-trip", %{"id" => id} = params, socket) do
    result =
      update_trip(id, trip_attrs(params, socket.assigns.timezone), socket.assigns.ash_scope)

    {:noreply,
     if(match?({:ok, _}, result),
       do: reload(socket),
       else: put_flash(socket, :error, "Nie udało się zapisać trasy.")
     )}
  end

  def handle_event("delete", %{"kind" => kind, "id" => id}, socket) do
    result = destroy_expense(kind, id, socket.assigns.ash_scope)

    {:noreply,
     if(result == :ok,
       do: reload(socket),
       else: put_flash(socket, :error, "Nie udało się usunąć dokumentu.")
     )}
  end

  def handle_event("toggle-description", %{"id" => id}, socket) do
    description_visible? =
      Map.update(socket.assigns.description_visible?, id, true, &not/1)

    {:noreply, assign(socket, :description_visible?, description_visible?)}
  end

  def handle_event("sort", _params, socket), do: {:noreply, assign(socket, :sort_active?, true)}

  def handle_event("submit", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("submit", _params, socket) do
    case Delegations.complete_delegation(socket.assigns.delegation.id,
           scope: socket.assigns.ash_scope
         ) do
      {:ok, delegation} ->
        {:noreply, setup_socket(socket, load_delegation!(delegation.id, socket))}

      _ ->
        {:noreply, put_flash(socket, :error, "Nie udało się wysłać rozliczenia.")}
    end
  end

  defp setup_socket(socket, delegation) do
    transport =
      if delegation.status == :complete,
        do: nil,
        else:
          allow_upload(socket, :transport,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_upload_progress/3
          )

    socket = if transport, do: transport, else: socket

    socket =
      if delegation.status == :complete,
        do: socket,
        else:
          socket
          |> allow_upload(:accommodation,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_upload_progress/3
          )
          |> allow_upload(:other,
            accept: ~w(.pdf .png .jpg .jpeg),
            max_entries: 1,
            auto_upload: true,
            progress: &handle_upload_progress/3
          )

    socket
    |> assign(
      delegation: delegation,
      editable?: delegation.status == :in_progress,
      page_title: "Rozliczenie delegacji",
      sort_active?: false
    )
    |> assign_new(:description_visible?, fn -> %{} end)
    |> assign_summary()
  end

  defp load_delegation(id, socket),
    do:
      Delegations.get_delegation(id,
        scope: socket.assigns.ash_scope,
        load: [:accommodation_expenses, :other_expenses, transport_expenses: [:trips]],
        not_found_error?: false
      )

  defp load_delegation!(id, socket), do: elem(load_delegation(id, socket), 1)

  defp reload(socket), do: setup_socket(socket, load_delegation!(socket.assigns.delegation.id, socket))

  defp refresh_delegation(socket) do
    socket
    |> assign(:delegation, load_delegation!(socket.assigns.delegation.id, socket))
    |> assign_summary()
  end

  defp handle_upload_progress(_kind, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_upload_progress(kind, entry, socket) do
    socket =
      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             {:ok,
              create_expense(
                kind,
                socket.assigns.delegation.id,
                entry.client_name,
                path,
                socket.assigns.ash_scope
              )}
           end) do
        {:ok, _expense} -> refresh_delegation(socket)
        {:error, _reason} -> put_flash(socket, :error, "Nie udało się dodać dokumentu.")
      end

    {:noreply, socket}
  end

  defp create_expense(:transport, id, filename, path, scope) do
    %{delegation_id: id, original_filename: filename}
    |> Map.merge(DelegationExpenseExtractor.extract(path, :transport))
    |> Delegations.create_transport_expense(scope: scope)
  end

  defp create_expense(:accommodation, id, filename, path, scope),
    do:
      %{delegation_id: id, original_filename: filename}
      |> Map.merge(DelegationExpenseExtractor.extract(path, :accommodation))
      |> Delegations.create_accommodation_expense(scope: scope)

  defp create_expense(:other, id, filename, path, scope),
    do:
      %{delegation_id: id, original_filename: filename}
      |> Map.merge(DelegationExpenseExtractor.extract(path, :other))
      |> Delegations.create_other_expense(scope: scope)

  defp update_expense(kind, id, attrs, scope) do
    with {:ok, expense} <- get_expense(kind, id, scope) do
      case kind do
        "transport" -> Delegations.update_transport_expense(expense, attrs, scope: scope)
        "accommodation" -> Delegations.update_accommodation_expense(expense, attrs, scope: scope)
        "other" -> Delegations.update_other_expense(expense, attrs, scope: scope)
      end
    end
  end

  defp destroy_expense(kind, id, scope) do
    with {:ok, expense} <- get_expense(kind, id, scope) do
      case kind do
        "transport" -> Delegations.destroy_transport_expense(expense, scope: scope)
        "accommodation" -> Delegations.destroy_accommodation_expense(expense, scope: scope)
        "other" -> Delegations.destroy_other_expense(expense, scope: scope)
      end
    end
  end

  defp get_expense("transport", id, scope),
    do: Delegations.get_transport_expense(id, scope: scope, not_found_error?: false)

  defp get_expense("accommodation", id, scope),
    do: Delegations.get_accommodation_expense(id, scope: scope, not_found_error?: false)

  defp get_expense("other", id, scope), do: Delegations.get_other_expense(id, scope: scope, not_found_error?: false)

  defp update_trip(id, attrs, scope) do
    with {:ok, trip} <- Delegations.get_delegation_trip(id, scope: scope, not_found_error?: false) do
      Delegations.update_delegation_trip(trip, attrs, scope: scope)
    end
  end

  defp update_attrs(kind, params) do
    params
    |> Map.take([
      "document_number",
      "description",
      "locality",
      "arrival_date",
      "departure_date",
      "transport_type"
    ])
    |> maybe_put_amount(params["expense_amount"])
    |> maybe_atom(:transport_type, kind)
  end

  defp maybe_put_amount(attrs, nil), do: attrs

  defp maybe_put_amount(attrs, amount), do: Map.put(attrs, :expense_amount, Money.new(:PLN, Decimal.new(amount)))

  defp maybe_atom(attrs, _key, kind) when kind != "transport", do: attrs

  defp maybe_atom(attrs, key, _kind), do: Map.update(attrs, key, :other, &String.to_existing_atom/1)

  defp trip_attrs(params, timezone) do
    params
    |> Map.take(["departure_city", "arrival_city"])
    |> Map.put(
      "departure_datetime",
      parse_datetime(params["departure_date"], params["departure_time"], timezone)
    )
    |> Map.put(
      "arrival_datetime",
      parse_datetime(params["arrival_date"], params["arrival_time"], timezone)
    )
    |> maybe_put_description(params)
  end

  defp maybe_put_description(attrs, %{"description" => description}), do: Map.put(attrs, "description", description)

  defp maybe_put_description(attrs, _params), do: attrs

  defp parse_datetime("", _time, _timezone), do: nil
  defp parse_datetime(_date, "", _timezone), do: nil
  defp parse_datetime(nil, _time, _timezone), do: nil
  defp parse_datetime(_date, nil, _timezone), do: nil

  defp parse_datetime(date, time, timezone) do
    with {:ok, naive_datetime} <- NaiveDateTime.from_iso8601("#{date}T#{time}:00"),
         {:ok, datetime} <- DateTime.from_naive(naive_datetime, timezone) do
      datetime
    end
  end

  defp date_value(nil, _timezone), do: nil

  defp date_value(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%Y-%m-%d")
  end

  defp time_value(nil, _timezone), do: nil

  defp time_value(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%H:%M")
  end

  defp assign_summary(socket) do
    total =
      Enum.reduce(
        [
          socket.assigns.delegation.transport_expenses,
          socket.assigns.delegation.accommodation_expenses,
          socket.assigns.delegation.other_expenses
        ],
        Money.new(:PLN, 0),
        fn expenses, acc -> Enum.reduce(expenses, acc, &Money.add!(&2, &1.expense_amount)) end
      )

    advance = socket.assigns.delegation.advance_payment_amount
    comparison = Money.compare(total, advance)

    {label, balance} =
      if comparison in [:gt, :eq],
        do: {"Do dopłaty", Money.sub!(total, advance)},
        else: {"Pomniejszenie wypłaty", Money.sub!(advance, total)}

    assign(socket,
      total: total,
      balance_label: label,
      balance: balance
    )
  end

  defp sum(expenses), do: Enum.reduce(expenses, Money.new(:PLN, 0), &Money.add!(&2, &1.expense_amount))

  defp transport_label("railway"), do: "Kolej"
  defp transport_label("airplane"), do: "Samolot"
  defp transport_label("bus"), do: "Autobus"
  defp transport_label("other"), do: "Inne"

  defp transport_options do
    Enum.map(~w(railway airplane bus other), &{transport_label(&1), &1})
  end
end
