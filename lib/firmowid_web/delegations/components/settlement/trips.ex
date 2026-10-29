defmodule FirmowidWeb.Delegations.Components.Settlement.Trips do
  @moduledoc "Editable and read-only ticket-local route details for delegation settlements."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Delegations.DelegationExpense.Trip
  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.LiveView.Rendered

  @doc "Renders editable route fields without converting the ticket's local clock."
  @spec trip_fields(map()) :: Rendered.t()
  attr :trips, :list, required: true
  attr :editable?, :boolean, required: true
  attr :description_visible?, :map, required: true
  attr :trip_forms, :map, required: true

  def trip_fields(assigns) do
    ~H"""
    <section
      :for={{trip, index} <- Enum.with_index(@trips, 1)}
      :if={@editable?}
      id={"transport-trip-#{trip.id}"}
      class="mbs-4 border-bs border-grey-100 pbs-4"
    >
      <% trip_form = Map.fetch!(@trip_forms, trip.id) %>
      <p :if={length(@trips) > 1} class="mbe-3 text-sm font-medium text-grey-900">
        {gettext("Route %{number}", number: SettlementPresentation.roman_numeral(index))}
      </p>
      <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,18rem),1fr))] gap-4">
        <.endpoint_fields form={trip_form} prefix={:departure} title={gettext("Departure")} />
        <.endpoint_fields form={trip_form} prefix={:arrival} title={gettext("Arrival")} />
      </div>
      <% description_visible? =
        Map.get(@description_visible?, trip.id, trip_form[:description].value not in [nil, ""]) %>
      <.button
        type="button"
        variant="unstyled"
        class="cursor-pointer text-sm text-grey-700 underline underline-offset-4 active:text-grey-900"
        phx-click={if description_visible?, do: "hide-description", else: "show-description"}
        phx-value-id={trip.id}
        aria-expanded={to_string(description_visible?)}
        aria-controls={"trip-description-#{trip.id}"}
      >
        {if description_visible?, do: gettext("Hide description"), else: gettext("Add description")}
      </.button>
      <.input
        id={"trip-description-#{trip.id}"}
        field={trip_form[:description]}
        type="textarea"
        label={gettext("Description")}
        class={["mbs-3", !description_visible? && "hidden"]}
      />
    </section>
    """
  end

  attr :form, :map, required: true
  attr :prefix, :atom, required: true
  attr :title, :string, required: true

  defp endpoint_fields(assigns) do
    %{form: form, prefix: prefix} = assigns
    datetime = Trip.local_datetime(form.data, prefix)
    date = Map.get(form.source.raw_params, "#{prefix}_date", format(datetime, "%Y-%m-%d"))
    time = Map.get(form.source.raw_params, "#{prefix}_time", format(datetime, "%H:%M"))
    errors = datetime_errors(form, prefix, date, time)
    local_field = local_field(prefix)
    legacy? = is_nil(Map.fetch!(form.data, local_field)) && not is_nil(datetime)

    assigns =
      assign(assigns,
        date: date,
        time: time,
        errors: errors,
        date_errors: if(valid_date?(date) && !valid_time?(time), do: [], else: errors),
        time_errors: if(valid_time?(time) && !valid_date?(date), do: [], else: errors),
        legacy?: legacy?,
        city_field: city_field(prefix)
      )

    ~H"""
    <fieldset class="min-w-0">
      <legend class="mbe-3 text-sm font-medium text-grey-900">{@title}</legend>
      <.input
        id={"trip-#{@prefix}-city-#{@form.data.id}"}
        field={@form[@city_field]}
        type="text"
        label={gettext("City")}
        phx-debounce="400"
      />
      <div class="mbs-3 flex flex-wrap gap-3">
        <div class="min-w-0 flex-[1_1_11.5rem]">
          <.input
            id={"trip-#{@prefix}-date-#{@form.data.id}"}
            name={"#{@form.name}[#{@prefix}_date]"}
            value={@date}
            type="text"
            inputmode="numeric"
            label={gettext("Date (YYYY-MM-DD)")}
            placeholder="2026-10-25"
            aria-describedby={"trip-#{@prefix}-hint-#{@form.data.id}"}
            errors={@date_errors}
            show_error={false}
            input_class="tabular-nums"
            phx-debounce="400"
          />
        </div>
        <div class="min-w-0 flex-[1_1_7rem]">
          <.input
            id={"trip-#{@prefix}-time-#{@form.data.id}"}
            name={"#{@form.name}[#{@prefix}_time]"}
            value={@time}
            type="text"
            inputmode="numeric"
            label={gettext("Time (HH:MM)")}
            placeholder="08:30"
            aria-describedby={"trip-#{@prefix}-hint-#{@form.data.id}"}
            errors={@time_errors}
            show_error={false}
            input_class="tabular-nums"
            phx-debounce="400"
          />
        </div>
      </div>
      <p
        id={"trip-#{@prefix}-hint-#{@form.data.id}"}
        class={[
          "mbs-2 min-h-[3lh] text-sm",
          if(@errors == [], do: "text-grey-700", else: "text-brick-700")
        ]}
      >
        <%= cond do %>
          <% @errors != [] -> %>
            {Enum.join(@errors, " ")}
          <% @legacy? -> %>
            {gettext("Historical time in UTC. Check it against the ticket.")}
          <% true -> %>
            {gettext("Local date and time as printed on the ticket.")}
        <% end %>
      </p>
    </fieldset>
    """
  end

  @doc "Renders saved ticket clocks; historical UTC-only records are explicitly labelled."
  @spec trip_details(map()) :: Rendered.t()
  attr :trips, :list, required: true

  def trip_details(assigns) do
    ~H"""
    <section
      :for={{trip, index} <- Enum.with_index(@trips, 1)}
      class="mbs-4 border-bs border-grey-100 pbs-4 sm:col-span-2 lg:col-span-3"
    >
      <p :if={length(@trips) > 1} class="mbe-3 text-sm font-medium">
        {gettext("Route %{number}", number: SettlementPresentation.roman_numeral(index))}
      </p>
      <dl class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,15rem),1fr))] gap-4 text-sm">
        <div :for={
          {prefix, title} <- [{:departure, gettext("Departure")}, {:arrival, gettext("Arrival")}]
        }>
          <dt class="font-medium">{title}</dt>
          <dd class="mbs-2">
            {SettlementPresentation.present_value(Map.fetch!(trip, city_field(prefix)))}
          </dd>
          <dd class="mbs-1 tabular-nums">
            {format(Trip.local_datetime(trip, prefix), "%d.%m.%Y %H:%M") || "—"}
          </dd>
          <dd
            :if={is_nil(Map.fetch!(trip, local_field(prefix))) && Trip.local_datetime(trip, prefix)}
            class="mbs-1 text-grey-700"
          >
            {gettext("Historical time in UTC. Check it against the ticket.")}
          </dd>
        </div>
      </dl>
      <p
        :if={trip.description not in [nil, ""]}
        class="mbs-3 text-sm whitespace-pre-wrap text-grey-700"
      >
        {trip.description}
      </p>
    </section>
    """
  end

  defp datetime_errors(form, prefix, date, time) do
    cond do
      date in [nil, ""] && time in [nil, ""] ->
        Enum.map(
          form[local_field(prefix)].errors ++ form[utc_field(prefix)].errors,
          &translate_error/1
        )

      not valid_datetime?(date, time) ->
        [
          gettext("Enter both a full date (YYYY-MM-DD) and time (HH:MM). The draft has not been saved.")
        ]

      true ->
        Enum.map(
          form[local_field(prefix)].errors ++ form[utc_field(prefix)].errors,
          &translate_error/1
        )
    end
  end

  defp valid_datetime?(date, time), do: valid_date?(date) && valid_time?(time)
  defp valid_date?(date) when is_binary(date), do: match?({:ok, _}, Date.from_iso8601(date))
  defp valid_date?(_date), do: false

  defp valid_time?(time) when is_binary(time), do: match?({:ok, _}, Time.from_iso8601(time <> ":00"))

  defp valid_time?(_time), do: false
  defp format(nil, _pattern), do: nil
  defp format(datetime, pattern), do: Calendar.strftime(datetime, pattern)
  defp city_field(:departure), do: :departure_city
  defp city_field(:arrival), do: :arrival_city
  defp local_field(:departure), do: :departure_local_datetime
  defp local_field(:arrival), do: :arrival_local_datetime
  defp utc_field(:departure), do: :departure_datetime
  defp utc_field(:arrival), do: :arrival_datetime
end
