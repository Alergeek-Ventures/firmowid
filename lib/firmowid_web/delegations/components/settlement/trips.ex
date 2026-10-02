defmodule FirmowidWeb.Delegations.Components.Settlement.Trips do
  @moduledoc "Editable and read-only transport trip components for delegation settlements."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation
  alias Phoenix.LiveView.Rendered

  @doc "Renders editable route fields for transport expense trips."
  @spec trip_fields(map()) :: Rendered.t()
  attr :trips, :list, required: true
  attr :editable?, :boolean, required: true
  attr :timezone, :string, required: true
  attr :description_visible?, :map, required: true
  attr :trip_forms, :map, required: true

  def trip_fields(assigns) do
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
          <table class="block w-full border-separate border-spacing-y-3 text-left text-sm sm:table sm:w-auto">
            <thead class="text-grey-500 hidden sm:table-header-group">
              <tr>
                <th scope="col"></th>
                <th scope="col" class="font-normal">Miejscowość</th>
                <th scope="col" class="font-normal">Data</th>
                <th scope="col" class="font-normal">Godzina</th>
                <th scope="col"></th>
              </tr>
            </thead>
            <tbody class="block sm:table-row-group">
              <tr class="grid grid-cols-2 gap-3 sm:table-row">
                <th scope="row" class="text-grey-700 col-span-full font-normal sm:table-cell sm:pr-3">
                  Wyjazd
                </th>
                <td class="col-span-full block sm:table-cell sm:pr-3">
                  <.input
                    id={"trip-departure-city-#{trip.id}"}
                    field={trip_form[:departure_city]}
                    type="text"
                    new
                    aria-label="Miejscowość wyjazdu"
                    input_class="w-full sm:w-36"
                  />
                </td>
                <td class="block sm:table-cell sm:pr-3">
                  <.input
                    id={"trip-departure-date-#{trip.id}"}
                    name={"#{trip_form.name}[departure_date]"}
                    value={
                      trip_form.params["departure_date"] ||
                        date_value(trip_form[:departure_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:departure_datetime])}
                    type="date"
                    new
                    aria-label="Data wyjazdu"
                    input_class="w-full sm:w-34"
                  />
                </td>
                <td class="block sm:table-cell">
                  <.input
                    id={"trip-departure-time-#{trip.id}"}
                    name={"#{trip_form.name}[departure_time]"}
                    value={
                      trip_form.params["departure_time"] ||
                        time_value(trip_form[:departure_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:departure_datetime])}
                    type="time"
                    new
                    aria-label="Godzina wyjazdu"
                    input_class="w-full sm:w-24"
                  />
                </td>
                <td
                  rowspan="2"
                  class="col-span-full block sm:table-cell sm:w-24 sm:pl-3 sm:align-bottom"
                >
                  <% description_visible? = Map.get(@description_visible?, trip.id, false) %>
                  <.button
                    type="button"
                    variant="unstyled"
                    class={[
                      "block w-full cursor-pointer text-left text-sm font-normal whitespace-nowrap sm:w-24",
                      description_visible? && "text-red-700"
                    ]}
                    phx-click={
                      if description_visible?, do: "hide-description", else: "show-description"
                    }
                    phx-value-id={trip.id}
                  >{if description_visible?, do: "Usuń opis", else: "Dodaj opis"}</.button>
                </td>
              </tr>
              <tr class="mt-4 grid grid-cols-2 gap-3 sm:mt-0 sm:table-row">
                <th scope="row" class="text-grey-700 col-span-full font-normal sm:table-cell sm:pr-3">
                  Przyjazd
                </th>
                <td class="col-span-full block sm:table-cell sm:pr-3">
                  <.input
                    id={"trip-arrival-city-#{trip.id}"}
                    field={trip_form[:arrival_city]}
                    type="text"
                    new
                    aria-label="Miejscowość przyjazdu"
                    input_class="w-full sm:w-36"
                  />
                </td>
                <td class="block sm:table-cell sm:pr-3">
                  <.input
                    id={"trip-arrival-date-#{trip.id}"}
                    name={"#{trip_form.name}[arrival_date]"}
                    value={
                      trip_form.params["arrival_date"] ||
                        date_value(trip_form[:arrival_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:arrival_datetime])}
                    type="date"
                    new
                    aria-label="Data przyjazdu"
                    input_class="w-full sm:w-34"
                  />
                </td>
                <td class="block sm:table-cell">
                  <.input
                    id={"trip-arrival-time-#{trip.id}"}
                    name={"#{trip_form.name}[arrival_time]"}
                    value={
                      trip_form.params["arrival_time"] ||
                        time_value(trip_form[:arrival_datetime].value, @timezone)
                    }
                    errors={translated_errors(trip_form[:arrival_datetime])}
                    type="time"
                    new
                    aria-label="Godzina przyjazdu"
                    input_class="w-full sm:w-24"
                  />
                </td>
              </tr>
              <tr
                :if={
                  Map.get(@description_visible?, trip.id, false) ||
                    trip_form[:description].value not in [nil, ""]
                }
                class="block sm:table-row"
              >
                <th
                  scope="row"
                  class="text-grey-700 block pt-2 font-normal sm:table-cell sm:pr-3 sm:align-top"
                >
                  Opis
                </th>
                <td colspan="4" class="block sm:table-cell">
                  <.input
                    id={"trip-description-#{trip.id}"}
                    field={trip_form[:description]}
                    type="textarea"
                    new
                    aria-label="Opis"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  @doc "Renders saved route details for transport expense trips."
  @spec trip_details(map()) :: Rendered.t()
  attr :trips, :list, required: true
  attr :timezone, :string, required: true

  def trip_details(assigns) do
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
        <dl class="mt-3"><.trip_detail label="Opis" value={trip.description} /></dl>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp trip_detail(assigns) do
    ~H"""
    <div>
      <dt class="text-grey-500">{@label}</dt>
      <dd class="text-grey-700 mt-1 whitespace-pre-wrap">
        {SettlementPresentation.present_value(@value)}
      </dd>
    </div>
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
end
