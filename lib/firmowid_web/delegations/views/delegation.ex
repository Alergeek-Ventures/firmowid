defmodule FirmowidWeb.Delegations.Views.Delegation do
  @moduledoc "Settlement page for an approved business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

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
            upload={Map.get(assigns[:uploads] || %{}, :transport)}
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
            upload={Map.get(assigns[:uploads] || %{}, :accommodation)}
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
            upload={Map.get(assigns[:uploads] || %{}, :other)}
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
            disabled={@uploading?}
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
          :if={@kind == "transport" && @editable?}
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
        <div
          :if={!@editable? && @expenses == []}
          id={"#{@kind}-empty-state"}
          class="text-grey-500 px-4 py-5 text-sm"
        >
          Nie dodano żadnych wydatków w tej kategorii.
        </div>
        <article
          :for={expense <- @expenses}
          class={["border-grey-200 rounded-lg border p-4", !@editable? && "bg-white"]}
        >
          <div class="text-grey-500 flex items-center justify-between gap-3 text-sm">
            <.link
              :if={expense.blob}
              kind="unstyled"
              external={expense.blob.url}
              target="_blank"
              rel="noopener noreferrer"
              class="flex min-w-0 items-center gap-2 truncate hover:underline"
            ><.icon name="hero-document" class="size-5 shrink-0" />{expense.original_filename}</.link>
            <span :if={!expense.blob} class="flex min-w-0 items-center gap-2 truncate"><.icon
              name="hero-document"
              class="size-5 shrink-0"
            />{expense.original_filename}</span>
            <.link
              :if={!@editable? && expense.blob}
              kind="button"
              external={expense.blob.url}
              variant="secondary"
              size="small"
              download={expense.original_filename}
              class="shrink-0"
            >
              <Lucideicons.download class="size-4" /> Pobierz
            </.link>
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
          <.expense_details
            :if={!@editable?}
            expense={expense}
            kind={@kind}
            timezone={@timezone}
          />
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

  attr :kind, :string, required: true

  defp pending_expense_form(%{kind: "transport"} = assigns) do
    ~H"""
    <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.skeleton_field label="Środek lokomocji" />
      <.skeleton_field label="Nr dokumentu" shimmer? />
      <.skeleton_amount_field />
    </div>
    <div class="border-grey-100 mt-4 border-t pt-4">
      <table class="border-separate border-spacing-y-3 text-left text-sm">
        <thead class="text-grey-500">
          <tr>
            <th scope="col"></th>
            <th scope="col" class="font-normal">Miejscowość</th>
            <th scope="col" class="font-normal">Data</th>
            <th scope="col" class="font-normal">Godzina</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th scope="row" class="text-grey-700 pr-3 font-normal">Wyjazd</th>
            <td class="pr-3"><.skeleton_blob class="w-[237px] min-w-[237px]" /></td>
            <td class="pr-3"><.skeleton_blob class="w-[172px] min-w-[172px]" /></td>
            <td><.skeleton_blob class="w-[91px] min-w-[91px]" /></td>
          </tr>
          <tr>
            <th scope="row" class="text-grey-700 pr-3 font-normal">Przyjazd</th>
            <td class="pr-3"><.skeleton_blob class="w-[237px] min-w-[237px]" /></td>
            <td class="pr-3"><.skeleton_blob class="w-[172px] min-w-[172px]" /></td>
            <td><.skeleton_blob class="w-[91px] min-w-[91px]" /></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp pending_expense_form(%{kind: "accommodation"} = assigns) do
    ~H"""
    <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.skeleton_field label="Miejscowość" />
      <.skeleton_field label="Nr dokumentu" shimmer? />
      <.skeleton_amount_field />
      <.skeleton_field label="Zameldowanie" />
      <.skeleton_field label="Wymeldowanie" />
    </div>
    """
  end

  defp pending_expense_form(%{kind: "other"} = assigns) do
    ~H"""
    <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <.skeleton_field label="Nr dokumentu" shimmer? />
      <.skeleton_amount_field />
      <.skeleton_field label="Opis" class="col-span-full" />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :shimmer?, :boolean, default: false

  defp skeleton_field(assigns) do
    ~H"""
    <div class={["w-full min-w-0", @class]}>
      <div class="text-grey-700 mb-2 flex items-center gap-1 text-sm/6">
        <Lucideicons.sparkles :if={@shimmer?} class="size-4" aria-hidden="true" />
        {@label}
      </div>
      <.skeleton_blob />
    </div>
    """
  end

  defp skeleton_amount_field(assigns) do
    ~H"""
    <div class="w-full min-w-0">
      <div class="text-grey-700 mb-2 flex items-center gap-1 text-sm/6">
        <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Kwota
      </div>
      <div class="flex items-end gap-2">
        <.skeleton_blob class="flex-1" />
        <span class="text-grey-500 shrink-0 pb-2 text-sm whitespace-nowrap">PLN</span>
      </div>
    </div>
    """
  end

  attr :class, :any, default: nil

  defp skeleton_blob(assigns) do
    ~H"""
    <div class={[
      "bg-grey-200 border-grey-200 block h-9 min-h-9 w-full min-w-0 animate-pulse rounded-lg border",
      @class
    ]} />
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
    >
      <:label_slot>
        <span class="inline-flex items-center gap-1">
          <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Nr dokumentu
        </span>
      </:label_slot>
    </.input>
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
          aria-describedby={"expense-amount-currency-#{@expense.id}"}
        >
          <:label_slot>
            <span class="inline-flex items-center gap-1">
              <Lucideicons.sparkles class="size-4" aria-hidden="true" /> Kwota
            </span>
          </:label_slot>
        </.input>
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

  attr :expense, :map, required: true
  attr :kind, :string, required: true
  attr :timezone, :string, required: true

  defp expense_details(assigns) do
    ~H"""
    <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-3">
      <.expense_detail
        :if={@kind == "transport"}
        label="Środek lokomocji"
        value={transport_label(to_string(@expense.transport_type))}
      />
      <.expense_detail label="Nr dokumentu" value={@expense.document_number} />
      <.expense_detail label="Kwota" value={Money.to_string!(@expense.expense_amount)} />
      <.expense_detail :if={@kind == "accommodation"} label="Miejscowość" value={@expense.locality} />
      <.expense_detail
        :if={@kind == "accommodation"}
        label="Zameldowanie"
        value={format_expense_date(@expense.arrival_date)}
      />
      <.expense_detail
        :if={@kind == "accommodation"}
        label="Wymeldowanie"
        value={format_expense_date(@expense.departure_date)}
      />
      <.expense_detail
        :if={@kind in ["accommodation", "other"]}
        label="Opis"
        value={@expense.description}
        class="sm:col-span-2 lg:col-span-3"
      />
      <.trip_details
        :if={@kind == "transport"}
        trips={@expense.trips || []}
        timezone={@timezone}
      />
    </dl>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :class, :any, default: nil

  defp expense_detail(assigns) do
    ~H"""
    <div class={@class}>
      <dt class="text-grey-500">{@label}</dt>
      <dd class="text-grey-700 mt-1 whitespace-pre-wrap">{present_expense_value(@value)}</dd>
    </div>
    """
  end

  attr :trips, :list, required: true
  attr :timezone, :string, required: true

  defp trip_details(assigns) do
    ~H"""
    <section
      :for={{trip, index} <- Enum.with_index(@trips, 1)}
      class={[
        "border-grey-100 mt-1 border-t pt-4 sm:col-span-2 lg:col-span-3",
        length(@trips) > 1 && "grid grid-cols-[1.5rem_minmax(0,1fr)] gap-x-4"
      ]}
    >
      <span
        :if={length(@trips) > 1}
        class="text-grey-900 self-center text-center text-sm font-medium"
      >
        {roman_numeral(index)}
      </span>
      <div class={[length(@trips) > 1 && "border-grey-200 border-l pl-4"]}>
        <table class="border-separate border-spacing-y-3 text-left text-sm">
          <thead class="text-grey-500">
            <tr>
              <th scope="col"></th>
              <th scope="col" class="font-normal">Miejscowość</th>
              <th scope="col" class="font-normal">Data</th>
              <th scope="col" class="font-normal">Godzina</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <th scope="row" class="text-grey-700 pr-3 font-normal">Wyjazd</th>
              <td class="pr-3">{present_expense_value(trip.departure_city)}</td>
              <td class="pr-3">
                {format_expense_date(datetime_date(trip.departure_datetime, @timezone))}
              </td>
              <td>{format_expense_time(trip.departure_datetime, @timezone)}</td>
            </tr>
            <tr>
              <th scope="row" class="text-grey-700 pr-3 font-normal">Przyjazd</th>
              <td class="pr-3">{present_expense_value(trip.arrival_city)}</td>
              <td class="pr-3">
                {format_expense_date(datetime_date(trip.arrival_datetime, @timezone))}
              </td>
              <td>{format_expense_time(trip.arrival_datetime, @timezone)}</td>
            </tr>
          </tbody>
        </table>
        <dl class="mt-3">
          <.expense_detail label="Opis" value={trip.description} />
        </dl>
      </div>
    </section>
    """
  end

  attr :trips, :list, required: true
  attr :editable?, :boolean, required: true
  attr :timezone, :string, required: true
  attr :description_visible?, :map, required: true

  defp trip_fields(assigns) do
    ~H"""
    <section
      :for={{trip, index} <- Enum.with_index(@trips, 1)}
      :if={@editable?}
      class={[
        "border-grey-100 mt-4 border-t pt-4",
        length(@trips) > 1 && "grid grid-cols-[1.5rem_minmax(0,1fr)] gap-x-4"
      ]}
    >
      <span
        :if={length(@trips) > 1}
        class="text-grey-900 self-center text-center text-sm font-medium"
      >
        {roman_numeral(index)}
      </span>
      <form
        id={"transport-trip-#{trip.id}"}
        phx-change="update-trip"
        phx-value-id={trip.id}
        class={[
          length(@trips) > 1 && "border-grey-200 border-l pl-4"
        ]}
      >
        <div class="min-w-0">
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
        </div>
      </form>
    </section>
    """
  end

  defp roman_numeral(number) do
    [
      {1000, "M"},
      {900, "CM"},
      {500, "D"},
      {400, "CD"},
      {100, "C"},
      {90, "XC"},
      {50, "L"},
      {40, "XL"},
      {10, "X"},
      {9, "IX"},
      {5, "V"},
      {4, "IV"},
      {1, "I"}
    ]
    |> Enum.reduce({number, ""}, fn {value, numeral}, {remainder, result} ->
      count = div(remainder, value)
      {remainder - count * value, result <> String.duplicate(numeral, count)}
    end)
    |> elem(1)
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
      <.pending_expense_form kind={@kind} />
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
  def handle_event("upload", _params, socket), do: {:noreply, assign(socket, :uploading?, true)}

  def handle_event("update", %{"kind" => kind, "id" => id} = params, socket) do
    result =
      with {:ok, attrs} <- update_attrs(kind, params) do
        update_expense(kind, id, attrs, socket.assigns.ash_scope)
      end

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

  def handle_event("sort", _params, socket) do
    delegation =
      Map.update!(socket.assigns.delegation, :transport_expenses, &sort_transport_expenses/1)

    {:noreply, assign(socket, delegation: delegation, sort_active?: true)}
  end

  def handle_event("submit", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("submit", _params, %{assigns: %{uploading?: true}} = socket), do: {:noreply, socket}

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
    sort_active? = socket.assigns[:sort_active?] || false
    delegation = maybe_sort_transport_expenses(delegation, sort_active?)

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
      uploading?: false,
      page_title: "Rozliczenie delegacji",
      sort_active?: sort_active?
    )
    |> assign_new(:description_visible?, fn -> %{} end)
    |> assign_summary()
  end

  defp load_delegation(id, socket),
    do:
      Delegations.get_delegation(id,
        scope: socket.assigns.ash_scope,
        load: [
          accommodation_expenses: [blob: [:url]],
          other_expenses: [blob: [:url]],
          transport_expenses: [:trips, blob: [:url]]
        ],
        not_found_error?: false
      )

  defp load_delegation!(id, socket), do: elem(load_delegation(id, socket), 1)

  defp reload(socket), do: setup_socket(socket, load_delegation!(socket.assigns.delegation.id, socket))

  defp refresh_delegation(socket) do
    socket
    |> assign(
      :delegation,
      socket.assigns.delegation.id
      |> load_delegation!(socket)
      |> maybe_sort_transport_expenses(socket.assigns.sort_active?)
    )
    |> assign_summary()
  end

  defp maybe_sort_transport_expenses(delegation, false), do: delegation

  defp maybe_sort_transport_expenses(delegation, true) do
    Map.update!(delegation, :transport_expenses, &sort_transport_expenses/1)
  end

  defp sort_transport_expenses(expenses) do
    Enum.sort_by(
      expenses,
      fn expense ->
        case expense.trips do
          [%{departure_datetime: %DateTime{} = departure_datetime}] ->
            {0, DateTime.to_unix(departure_datetime, :microsecond), expense.inserted_at, expense.id}

          _ ->
            {1, 0, expense.inserted_at, expense.id}
        end
      end,
      :asc
    )
  end

  defp handle_upload_progress(_kind, %{done?: false}, socket), do: {:noreply, assign(socket, :uploading?, true)}

  defp handle_upload_progress(kind, entry, socket) do
    socket =
      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             {:ok,
              create_expense(
                kind,
                socket.assigns.delegation.id,
                entry.client_name,
                entry.client_type,
                path,
                socket.assigns.ash_scope
              )}
           end) do
        {:ok, _expense} -> refresh_delegation(socket)
        {:error, _reason} -> put_flash(socket, :error, "Nie udało się dodać dokumentu.")
      end

    {:noreply, assign(socket, :uploading?, uploads_in_progress?(socket))}
  end

  defp create_expense(:transport, id, filename, content_type, path, scope) do
    %{
      delegation_id: id,
      original_filename: filename,
      document_number: "",
      expense_amount: Money.new(:PLN, 0),
      upload_path: path,
      content_type: content_type
    }
    |> Map.merge(DelegationExpenseExtractor.extract(path, :transport))
    |> Delegations.create_transport_expense(scope: scope)
  end

  defp create_expense(:accommodation, id, filename, content_type, path, scope),
    do:
      %{
        delegation_id: id,
        original_filename: filename,
        document_number: "",
        expense_amount: Money.new(:PLN, 0),
        upload_path: path,
        content_type: content_type
      }
      |> Map.merge(DelegationExpenseExtractor.extract(path, :accommodation))
      |> Delegations.create_accommodation_expense(scope: scope)

  defp create_expense(:other, id, filename, content_type, path, scope),
    do:
      %{
        delegation_id: id,
        original_filename: filename,
        document_number: "",
        expense_amount: Money.new(:PLN, 0),
        upload_path: path,
        content_type: content_type
      }
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
    with {:ok, attrs} <-
           maybe_put_amount(Map.take(params, expense_fields()), params["expense_amount"]) do
      validate_transport_type(attrs, kind)
    end
  end

  defp expense_fields,
    do: ["document_number", "description", "locality", "arrival_date", "departure_date", "transport_type"]

  defp maybe_put_amount(attrs, nil), do: {:ok, attrs}

  defp maybe_put_amount(attrs, amount) do
    case Decimal.parse(amount) do
      {decimal, ""} -> {:ok, Map.put(attrs, :expense_amount, Money.new(:PLN, decimal))}
      _ -> :error
    end
  end

  defp validate_transport_type(attrs, kind) when kind != "transport", do: {:ok, attrs}

  defp validate_transport_type(attrs, _kind) do
    if attrs["transport_type"] in ~w(railway airplane bus other), do: {:ok, attrs}, else: :error
  end

  defp uploads_in_progress?(socket) do
    Enum.any?([:transport, :accommodation, :other], fn name ->
      {_completed, in_progress} = uploaded_entries(socket, name)
      in_progress != []
    end)
  end

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

  defp format_expense_date(nil), do: "—"
  defp format_expense_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp datetime_date(nil, _timezone), do: nil

  defp datetime_date(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
  end

  defp format_expense_time(nil, _timezone), do: "—"

  defp format_expense_time(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%H:%M")
  end

  defp present_expense_value(value) when value in [nil, ""], do: "—"
  defp present_expense_value(value), do: value

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
