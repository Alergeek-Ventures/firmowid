defmodule FirmowidWeb.Delegations.Views.Delegation do
  @moduledoc "Settlement page for an approved business trip delegation."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias AshPhoenix.Form.Auto
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Delegations.DelegationExpenseExtractor
  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.HTML.Form

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
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :transport)}
            upload={Map.get(assigns[:uploads] || %{}, :transport)}
            upload_form={Map.fetch!(@upload_forms, "transport")}
            kind="transport"
            editable?={@editable?}
            sort_active?={@sort_active?}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            timezone={@timezone}
          >
            <:icon><Lucideicons.plane class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title="Nocleg"
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :accommodation)}
            upload={Map.get(assigns[:uploads] || %{}, :accommodation)}
            upload_form={Map.fetch!(@upload_forms, "accommodation")}
            kind="accommodation"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
            timezone={@timezone}
          >
            <:icon><Lucideicons.bed_double class="size-5" /></:icon>
          </.expense_section>
          <.expense_section
            title="Inne wydatki"
            expenses={SettlementPresentation.expenses_for(@delegation.expenses, :other)}
            upload={Map.get(assigns[:uploads] || %{}, :other)}
            upload_form={Map.fetch!(@upload_forms, "other")}
            kind="other"
            editable?={@editable?}
            sort_active?={false}
            description_visible?={@description_visible?}
            expense_forms={@expense_forms}
            trip_forms={@trip_forms}
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
              <.summary_row
                label="Przejazdy"
                value={
                  SettlementPresentation.sum(
                    SettlementPresentation.expenses_for(@delegation.expenses, :transport)
                  )
                }
              />
              <.summary_row
                label="Nocleg"
                value={
                  SettlementPresentation.sum(
                    SettlementPresentation.expenses_for(@delegation.expenses, :accommodation)
                  )
                }
              />
              <.summary_row
                label="Inne"
                value={
                  SettlementPresentation.sum(
                    SettlementPresentation.expenses_for(@delegation.expenses, :other)
                  )
                }
              />
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
          <.form
            :if={@editable?}
            for={@complete_form}
            id="delegation-complete-form"
            phx-change="validate"
            phx-submit="submit"
            class="mt-6"
          >
            <.nested_hidden_inputs form={@complete_form} />
            <.button
              :if={@editable?}
              type="submit"
              variant="primary"
              accent="turquoise"
              size="big"
              class="w-full"
              disabled={@uploading?}
            >Wyślij</.button>
          </.form>
        </aside>
      </main>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :icon, required: true
  attr :expenses, :list, required: true
  attr :upload, :any, required: true
  attr :upload_form, Form, required: true
  attr :kind, :string, required: true
  attr :editable?, :boolean, required: true
  attr :sort_active?, :boolean, required: true
  attr :description_visible?, :map, default: %{}
  attr :expense_forms, :map, required: true
  attr :trip_forms, :map, required: true
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
          <% expense_form = Map.fetch!(@expense_forms, expense.id) %>
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
          <div
            :if={@editable?}
            id={"#{@kind}-expense-#{expense.id}"}
            class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
          >
            <.input
              :if={@kind == "transport"}
              id={"#{@kind}-transport-type-#{expense.id}"}
              field={expense_form[:transport_type]}
              form="delegation-complete-form"
              type="select"
              new
              label="Środek lokomocji"
              options={SettlementPresentation.transport_options()}
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-locality-#{expense.id}"}
              field={expense_form[:locality]}
              form="delegation-complete-form"
              type="text"
              new
              label="Miejscowość"
            />
            <.document_fields expense={expense} form={expense_form} />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-arrival-date-#{expense.id}"}
              field={expense_form[:arrival_date]}
              form="delegation-complete-form"
              type="date"
              new
              label="Zameldowanie"
            />
            <.input
              :if={@kind == "accommodation"}
              id={"#{@kind}-departure-date-#{expense.id}"}
              field={expense_form[:departure_date]}
              form="delegation-complete-form"
              type="date"
              new
              label="Wymeldowanie"
            />
            <.expense_description
              :if={@kind == "accommodation"}
              expense={expense}
              form={expense_form}
              kind={@kind}
              visible?={Map.get(@description_visible?, expense.id, false)}
            />
            <.input
              :if={@kind == "other"}
              id={"#{@kind}-description-#{expense.id}"}
              field={expense_form[:description]}
              form="delegation-complete-form"
              type="textarea"
              new
              label="Opis"
              class="col-span-full"
            />
          </div>
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
            trip_forms={@trip_forms}
          />
        </article>
        <.pending_expense
          :for={entry <- if(@upload, do: @upload.entries, else: [])}
          entry={entry}
          kind={@kind}
        />
        <.form
          :if={@editable? && @upload}
          for={@upload_form}
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
        </.form>
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
  attr :form, Form, required: true

  defp document_fields(assigns) do
    ~H"""
    <.input
      id={"document-number-#{@expense.id}"}
      field={@form[:document_number]}
      form="delegation-complete-form"
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
          field={@form[:expense_amount]}
          form="delegation-complete-form"
          value={expense_amount_value(@form[:expense_amount].value)}
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
        value={SettlementPresentation.transport_label(to_string(@expense.transport_type))}
      />
      <.expense_detail label="Nr dokumentu" value={@expense.document_number} />
      <.expense_detail label="Kwota" value={Money.to_string!(@expense.expense_amount)} />
      <.expense_detail :if={@kind == "accommodation"} label="Miejscowość" value={@expense.locality} />
      <.expense_detail
        :if={@kind == "accommodation"}
        label="Zameldowanie"
        value={SettlementPresentation.format_date(@expense.arrival_date)}
      />
      <.expense_detail
        :if={@kind == "accommodation"}
        label="Wymeldowanie"
        value={SettlementPresentation.format_date(@expense.departure_date)}
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
      <dd class="text-grey-700 mt-1 whitespace-pre-wrap">
        {SettlementPresentation.present_value(@value)}
      </dd>
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
        {SettlementPresentation.roman_numeral(index)}
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
              <td class="pr-3">{SettlementPresentation.present_value(trip.departure_city)}</td>
              <td class="pr-3">
                {SettlementPresentation.format_date(
                  SettlementPresentation.datetime_date(trip.departure_datetime, @timezone)
                )}
              </td>
              <td>{SettlementPresentation.format_time(trip.departure_datetime, @timezone)}</td>
            </tr>
            <tr>
              <th scope="row" class="text-grey-700 pr-3 font-normal">Przyjazd</th>
              <td class="pr-3">{SettlementPresentation.present_value(trip.arrival_city)}</td>
              <td class="pr-3">
                {SettlementPresentation.format_date(
                  SettlementPresentation.datetime_date(trip.arrival_datetime, @timezone)
                )}
              </td>
              <td>{SettlementPresentation.format_time(trip.arrival_datetime, @timezone)}</td>
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
  attr :trip_forms, :map, required: true

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
      <% trip_form = Map.fetch!(@trip_forms, trip.id) %>
      <span
        :if={length(@trips) > 1}
        class="text-grey-900 self-center text-center text-sm font-medium"
      >
        {SettlementPresentation.roman_numeral(index)}
      </span>
      <div
        id={"transport-trip-#{trip.id}"}
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
                    field={trip_form[:departure_city]}
                    form="delegation-complete-form"
                    type="text"
                    new
                    aria-label="Miejscowość wyjazdu"
                    input_class="w-36"
                  />
                </td>
                <td class="pr-3">
                  <.input
                    id={"trip-departure-date-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[departure_date]"}
                    value={date_value(trip.departure_datetime, @timezone)}
                    errors={translated_errors(trip_form[:departure_datetime])}
                    type="date"
                    new
                    aria-label="Data wyjazdu"
                    input_class="w-34"
                  />
                </td>
                <td>
                  <.input
                    id={"trip-departure-time-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[departure_time]"}
                    value={time_value(trip.departure_datetime, @timezone)}
                    errors={translated_errors(trip_form[:departure_datetime])}
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
                    field={trip_form[:arrival_city]}
                    form="delegation-complete-form"
                    type="text"
                    new
                    aria-label="Miejscowość przyjazdu"
                    input_class="w-36"
                  />
                </td>
                <td class="pr-3">
                  <.input
                    id={"trip-arrival-date-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[arrival_date]"}
                    value={date_value(trip.arrival_datetime, @timezone)}
                    errors={translated_errors(trip_form[:arrival_datetime])}
                    type="date"
                    new
                    aria-label="Data przyjazdu"
                    input_class="w-34"
                  />
                </td>
                <td>
                  <.input
                    id={"trip-arrival-time-#{trip.id}"}
                    form="delegation-complete-form"
                    name={"#{trip_form.name}[arrival_time]"}
                    value={time_value(trip.arrival_datetime, @timezone)}
                    errors={translated_errors(trip_form[:arrival_datetime])}
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
            field={trip_form[:description]}
            form="delegation-complete-form"
            type="textarea"
            new
            label="Opis"
          />
        </div>
      </div>
    </section>
    """
  end

  attr :expense, :any, required: true
  attr :form, Form, required: true
  attr :kind, :string, required: true
  attr :visible?, :boolean, required: true

  defp expense_description(assigns) do
    ~H"""
    <div class="col-span-full flex flex-col items-end gap-2">
      <.input
        :if={@visible?}
        id={"#{@kind}-description-#{@expense.id}"}
        field={@form[:description]}
        form="delegation-complete-form"
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

  def handle_event("validate", %{"delegation" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.complete_form, params)
    {:noreply, assign_complete_form(socket, form)}
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
    delegation = Map.update!(socket.assigns.delegation, :expenses, &sort_transport_expenses/1)

    form =
      complete_form(socket.assigns.delegation, socket.assigns.ash_scope, socket.assigns.timezone)

    {:noreply,
     socket
     |> assign(delegation: delegation, sort_active?: true)
     |> assign_complete_form(form)}
  end

  def handle_event("submit", _params, %{assigns: %{editable?: false}} = socket), do: {:noreply, socket}

  def handle_event("submit", _params, %{assigns: %{uploading?: true}} = socket), do: {:noreply, socket}

  def handle_event("submit", params, socket) do
    params = Map.get(params, "delegation", %{})

    case AshPhoenix.Form.submit(socket.assigns.complete_form, params: params) do
      {:ok, delegation} ->
        {:noreply, setup_socket(socket, load_delegation!(delegation.id, socket))}

      {:error, complete_form} ->
        {:noreply, assign_complete_form(socket, complete_form)}
    end
  end

  defp setup_socket(socket, delegation) do
    sort_active? = socket.assigns[:sort_active?] || false
    complete_form = complete_form(delegation, socket.assigns.ash_scope, socket.assigns.timezone)
    delegation = decorate_delegation(delegation, sort_active?)

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
      sort_active?: sort_active?,
      upload_forms: upload_forms(socket.assigns.ash_scope)
    )
    |> assign_complete_form(complete_form)
    |> assign_new(:description_visible?, fn -> %{} end)
    |> assign_summary()
  end

  defp load_delegation(id, socket),
    do:
      Delegations.get_delegation(id,
        scope: socket.assigns.ash_scope,
        load: [expenses: [blob: [:url]]],
        not_found_error?: false
      )

  defp load_delegation!(id, socket), do: elem(load_delegation(id, socket), 1)

  defp reload(socket), do: setup_socket(socket, load_delegation!(socket.assigns.delegation.id, socket))

  defp refresh_delegation(socket) do
    delegation =
      socket.assigns.delegation.id
      |> load_delegation!(socket)
      |> decorate_delegation(socket.assigns.sort_active?)

    complete_form = complete_form(delegation, socket.assigns.ash_scope, socket.assigns.timezone)

    socket
    |> assign(
      delegation: delegation,
      upload_forms: upload_forms(socket.assigns.ash_scope)
    )
    |> assign_complete_form(complete_form)
    |> assign_summary()
  end

  defp decorate_delegation(delegation, sort_active?) do
    expenses =
      if sort_active?, do: sort_transport_expenses(delegation.expenses), else: delegation.expenses

    Map.put(delegation, :expenses, Enum.map(expenses, &decorate_expense/1))
  end

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Ash.Delegations.DelegationExpense.TransportDetails} = details} = expense
       ) do
    expense |> Map.put(:transport_type, details.transport_type) |> Map.put(:trips, details.trips)
  end

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Ash.Delegations.DelegationExpense.AccommodationDetails} = details} = expense
       ) do
    expense
    |> Map.put(:locality, details.locality)
    |> Map.put(:arrival_date, details.arrival_date)
    |> Map.put(:departure_date, details.departure_date)
    |> Map.put(:description, details.description)
  end

  defp decorate_expense(
         %{details: %{__struct__: Firmowid.Ash.Delegations.DelegationExpense.OtherDetails} = details} = expense
       ), do: Map.put(expense, :description, details.description)

  defp sort_transport_expenses(expenses) do
    Enum.sort_by(
      expenses,
      fn expense ->
        case Map.get(expense, :trips, []) do
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

  defp create_expense(kind, id, filename, content_type, path, scope) do
    with {:ok, extracted_details} <- DelegationExpenseExtractor.extract(path, kind) do
      create_expense_form(id, filename, content_type, path, kind, extracted_details, scope)
    end
  end

  defp create_expense_form(id, filename, content_type, path, kind, extracted_details, scope) do
    DelegationExpense
    |> AshPhoenix.Form.for_create(:create, scope: scope)
    |> AshPhoenix.Form.submit(
      params:
        Map.merge(
          %{
            delegation_id: id,
            kind: kind,
            original_filename: filename,
            document_number: "",
            expense_amount: Money.new(:PLN, 0),
            upload_path: path,
            content_type: content_type,
            details: initial_expense_details(kind)
          },
          extracted_details
        )
    )
  end

  defp initial_expense_details(:transport), do: %{type: "transport", transport_type: :other, trips: []}

  defp initial_expense_details(:accommodation), do: %{type: "accommodation", locality: ""}
  defp initial_expense_details(:other), do: %{type: "other", description: ""}

  defp destroy_expense(kind, id, scope) do
    with {:ok, expense} <- get_expense(kind, id, scope) do
      _ = kind
      Delegations.destroy_expense(expense, scope: scope)
    end
  end

  defp get_expense(_kind, id, scope), do: Delegations.get_expense(id, scope: scope, not_found_error?: false)

  defp complete_form(delegation, scope, timezone) do
    forms =
      Firmowid.Ash.Delegations.Delegation
      |> Auto.auto(:complete)
      |> Enum.map(fn {key, config} ->
        config =
          config |> Keyword.fetch!(:updater) |> then(& &1.(config)) |> Keyword.delete(:updater)

        config =
          if key == :expenses do
            Keyword.put(config, :transform_params, fn params, _type ->
              transform_expense_params(params, timezone)
            end)
          else
            config
          end

        {key, config}
      end)

    delegation
    |> AshPhoenix.Form.for_update(:complete,
      scope: scope,
      as: "delegation",
      forms: forms
    )
    |> to_form()
  end

  defp assign_complete_form(socket, form) do
    expense_forms =
      [:expenses]
      |> Enum.flat_map(&nested_forms(form, &1))
      |> Map.new(&{&1.data.id, &1})

    trip_forms = %{}

    assign(socket, complete_form: form, expense_forms: expense_forms, trip_forms: trip_forms)
  end

  defp nested_forms(%Form{source: source}, field) do
    source.forms
    |> Map.get(field, [])
    |> List.wrap()
    |> Enum.map(&to_form/1)
  end

  attr :form, Form, required: true

  defp nested_hidden_inputs(assigns) do
    children =
      assigns.form.source.forms
      |> Map.values()
      |> Enum.flat_map(&List.wrap/1)
      |> Enum.map(&to_form/1)

    assigns = assign(assigns, :children, children)

    ~H"""
    <%= for {name, values} <- @form.hidden, value <- List.wrap(values) do %>
      <input type="hidden" name={"#{@form.name}[#{name}]"} value={value} />
    <% end %>
    <.nested_hidden_inputs :for={child <- @children} form={child} />
    """
  end

  defp upload_forms(scope) do
    %{
      "transport" => upload_form(DelegationExpense, scope, "transport"),
      "accommodation" => upload_form(DelegationExpense, scope, "accommodation"),
      "other" => upload_form(DelegationExpense, scope, "other")
    }
  end

  defp upload_form(resource, scope, name) do
    resource
    |> AshPhoenix.Form.for_create(:create, scope: scope, as: name)
    |> to_form()
  end

  defp expense_amount_value(%Money{} = amount), do: Money.to_decimal(amount)
  defp expense_amount_value(amount), do: amount

  defp translated_errors(field), do: Enum.map(field.errors, &translate_error/1)

  defp uploads_in_progress?(socket) do
    Enum.any?([:transport, :accommodation, :other], fn name ->
      {_completed, in_progress} = uploaded_entries(socket, name)
      in_progress != []
    end)
  end

  defp transform_expense_params(%{"kind" => kind} = params, _timezone) do
    details =
      case kind do
        "transport" ->
          %{
            "type" => kind,
            "transport_type" => params["transport_type"] || "other",
            "trips" => []
          }

        "accommodation" ->
          params
          |> Map.take(["locality", "arrival_date", "departure_date", "description"])
          |> Map.put("type", kind)

        "other" ->
          params |> Map.take(["description"]) |> Map.put("type", kind)
      end

    params
    |> Map.take(["id", "_form_type", "document_number", "expense_amount"])
    |> Map.put("details", details)
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
    total = SettlementPresentation.sum(socket.assigns.delegation.expenses)

    advance = socket.assigns.delegation.advance_payment_amount
    {label, balance} = SettlementPresentation.settlement_balance(total, advance)

    assign(socket,
      total: total,
      balance_label: label,
      balance: balance
    )
  end
end
