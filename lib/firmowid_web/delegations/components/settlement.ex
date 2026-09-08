defmodule FirmowidWeb.Delegations.Components.Settlement do
  @moduledoc "Function components for the delegation settlement page."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Rendered

  @doc "Renders an expense category, its documents, and upload control."
  @spec expense_section(map()) :: Rendered.t()
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

  def expense_section(assigns) do
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

  @doc "Renders a money row in the settlement summary."
  @spec summary_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :value, Money, required: true
  attr :class, :string, default: ""

  def summary_row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @class]}>
      <dt>{@label}</dt><dd class={[Money.zero?(@value) && "text-grey-500"]}>
        {Money.to_string!(@value)}
      </dd>
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

  attr :expense, :any, required: true
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
      <.trip_details :if={@kind == "transport"} trips={@expense.trips || []} timezone={@timezone} />
    </dl>
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
      <span :if={length(@trips) > 1} class="text-grey-900 self-center text-center text-sm font-medium">
        {SettlementPresentation.roman_numeral(index)}
      </span>
      <div
        id={"transport-trip-#{trip.id}"}
        class={[length(@trips) > 1 && "border-grey-200 border-l pl-4"]}
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
      <span :if={length(@trips) > 1} class="text-grey-900 self-center text-center text-sm font-medium">
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
        <dl class="mt-3"><.expense_detail label="Opis" value={trip.description} /></dl>
      </div>
    </section>
    """
  end

  defp date_value(nil, _timezone), do: nil

  defp date_value(datetime, timezone) do
    datetime |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%Y-%m-%d")
  end

  defp time_value(nil, _timezone), do: nil

  defp time_value(datetime, timezone) do
    datetime |> DateTime.shift_zone!(timezone) |> Calendar.strftime("%H:%M")
  end

  defp translated_errors(field), do: Enum.map(field.errors, &translate_error/1)

  defp expense_amount_value(%Money{} = amount), do: Money.to_decimal(amount)
  defp expense_amount_value(amount), do: amount
end
