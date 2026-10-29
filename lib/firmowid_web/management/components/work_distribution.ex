defmodule FirmowidWeb.Management.Components.WorkDistribution do
  @moduledoc """
  Monthly calendars of an employee's worked hours. Selecting a day keeps only its week
  and shows the day's sessions on a time-of-day axis.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @colors ~w(bg-teal-600 bg-rust-400 bg-moss-400 bg-brick-500 bg-grey-400)
  @timezone "Europe/Warsaw"
  @axis_from 6
  @axis_to 22

  @doc """
  Renders one calendar per month in `months` (newest first). A selected day collapses
  every other month and week, and opens that day's sessions below its week.
  """
  @spec work_distribution(map()) :: Phoenix.LiveView.Rendered.t()
  attr :sessions, :list, required: true, doc: "Sessions with `:duration` and `:project` loaded."
  attr :months, :list, required: true, doc: "First days of the months to show, newest first."
  attr :selected_day, Date, default: nil
  attr :target, :any, required: true

  def work_distribution(assigns) do
    by_day = by_day(assigns.sessions)

    assigns =
      assign(assigns,
        months: Enum.map(assigns.months, &month(&1, by_day)),
        day_sessions: Map.get(by_day, assigns.selected_day, []),
        colors: project_colors(assigns.sessions),
        weekdays: weekdays()
      )

    ~H"""
    <div
      id="work-distribution"
      phx-hook=".ScrollToTop"
      data-selected-day={@selected_day}
      class="flex flex-col px-1 pt-1 pb-4"
    >
      <.collapsible
        :for={month <- @months}
        id={"work-month-#{month.date}"}
        collapsed={@selected_day != nil and Date.beginning_of_month(@selected_day) != month.date}
        phx-remove={collapse()}
      >
        <section class="flex flex-col gap-3 pb-7">
          <div class="flex items-baseline justify-between gap-4">
            <h4 class="text-base font-medium text-grey-900 first-letter:uppercase">
              {TimeFormatter.format_date(month.date, "LLLL yyyy")}
            </h4>
            <span class="text-sm font-medium text-grey-800 tabular-nums">{hours(month.seconds)} h</span>
          </div>
          <div class="flex flex-col">
            <div class={["grid items-center gap-x-1.5 px-1", week_styles()]}>
              <span :for={day <- @weekdays} class="text-center text-xs text-grey-600">{day}</span>
              <span class="text-right text-xs text-grey-600">{gettext("Week")}</span>
            </div>
            <.collapsible
              :for={week <- month.weeks}
              collapsed={@selected_day != nil and @selected_day not in week.dates}
            >
              <div class={["grid items-center gap-x-1.5 p-1", week_styles()]}>
                <%= for cell <- week.cells do %>
                  <span :if={cell.outside} class="h-14" />
                  <.button
                    :if={!cell.outside}
                    type="button"
                    variant="unstyled"
                    phx-click="select_day"
                    phx-value-date={Date.to_iso8601(cell.date)}
                    phx-target={@target}
                    aria-pressed={to_string(cell.date == @selected_day)}
                    aria-label={"#{Calendar.strftime(cell.date, "%d.%m")} · #{hours(cell.seconds)} h"}
                    class={[
                      "flex h-14 cursor-pointer flex-col items-center justify-center rounded-md leading-tight tabular-nums transition hover:brightness-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700",
                      intensity_styles(cell.seconds),
                      cell.date == @selected_day && "ring-2 ring-grey-900 ring-offset-2"
                    ]}
                  >
                    <span class="text-caps-sm opacity-70">{cell.date.day}</span>
                    <span :if={cell.seconds > 0} class="text-sm font-medium">{hours(cell.seconds)} h</span>
                  </.button>
                <% end %>
                <span class="text-right text-sm font-medium text-grey-800 tabular-nums">
                  {hours(week.seconds)} h
                </span>
              </div>
            </.collapsible>
          </div>
        </section>
      </.collapsible>

      <.day_details
        :if={@selected_day}
        date={@selected_day}
        sessions={@day_sessions}
        colors={@colors}
        target={@target}
      />

      <.collapsible collapsed={@selected_day != nil}>
        <div class="flex items-center gap-1.5 text-xs text-grey-600">
          {pgettext("work hours legend", "Less")}
          <span
            :for={h <- [0, 3, 5, 8, 10]}
            class={["size-3 rounded-sm", intensity_styles(h * 3600)]}
          />
          {pgettext("work hours legend", "More")}
        </div>
      </.collapsible>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToTop">
        export default {
          mounted() {
            this.selectedDay = this.el.dataset.selectedDay;
          },
          updated() {
            if (this.el.dataset.selectedDay === this.selectedDay) return;
            this.selectedDay = this.el.dataset.selectedDay;
            this.el.parentElement.scrollTo({ top: 0, behavior: "smooth" });
          },
        };
      </script>
    </div>
    """
  end

  @doc """
  Returns the UTC bounds `{from, to}` of sessions started in `months` (newest first), with
  months starting at midnight in the timezone the calendars group sessions into days by.
  """
  @spec started_range([Date.t()]) :: {DateTime.t(), DateTime.t()}
  def started_range(months) do
    {local_midnight(List.last(months)), months |> List.first() |> Date.shift(month: 1) |> local_midnight()}
  end

  defp local_midnight(date), do: date |> DateTime.new!(~T[00:00:00], @timezone) |> DateTime.shift_zone!("Etc/UTC")

  # Height and opacity animate between states, so collapsed content stays in the DOM.
  attr :collapsed, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  defp collapsible(assigns) do
    ~H"""
    <div
      data-collapsed={@collapsed}
      class="grid grid-rows-[1fr] transition-[grid-template-rows,opacity] duration-300 ease-in-out data-collapsed:grid-rows-[0fr] data-collapsed:opacity-0"
      {@rest}
    >
      <div class="min-h-0 overflow-hidden">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  # A month dropped from the list after switching months collapses before it is removed.
  defp collapse, do: {"data-collapsed", "true"} |> JS.set_attribute() |> JS.transition("pointer-events-none", time: 300)

  defp weekdays do
    [
      pgettext("weekday abbreviation", "Mo"),
      pgettext("weekday abbreviation", "Tu"),
      pgettext("weekday abbreviation", "We"),
      pgettext("weekday abbreviation", "Th"),
      pgettext("weekday abbreviation", "Fr"),
      pgettext("weekday abbreviation", "Sa"),
      pgettext("weekday abbreviation", "Su")
    ]
  end

  defp week_styles, do: "grid-cols-[repeat(7,minmax(0,1fr))_4rem]"

  attr :date, Date, required: true
  attr :sessions, :list, required: true
  attr :colors, :map, required: true
  attr :target, :any, required: true

  defp day_details(assigns) do
    blocks =
      assigns.sessions
      |> Enum.sort_by(&DateTime.to_unix(&1.start_datetime))
      |> Enum.map(fn session ->
        start = DateTime.shift_zone!(session.start_datetime, @timezone)
        from = start.hour + start.minute / 60

        %{
          id: session.id,
          project_id: session.project_id,
          project: session.project.name,
          title: session.title,
          seconds: session.duration,
          from: from,
          to: from + session.duration / 3600,
          range:
            "#{Calendar.strftime(start, "%H:%M")}–#{start |> DateTime.shift(second: session.duration) |> Calendar.strftime("%H:%M")}"
        }
      end)

    assigns =
      assign(assigns,
        blocks: blocks,
        axis_from: @axis_from,
        span: @axis_to - @axis_from,
        ticks: Enum.take_every(@axis_from..@axis_to, 4)
      )

    ~H"""
    <section
      id="work-day-details"
      phx-mounted={
        JS.transition(
          {"ease-out duration-300", "opacity-0 -translate-y-2", "opacity-100 translate-y-0"},
          time: 300
        )
      }
      phx-remove={JS.transition({"ease-in duration-200", "opacity-100", "opacity-0"}, time: 200)}
      class="flex flex-col gap-3 border-t border-grey-100 pt-4"
    >
      <div class="flex items-center justify-between gap-4">
        <h4 class="text-base font-medium text-grey-900 first-letter:uppercase">
          {TimeFormatter.format_date(@date, "EEEE, d MMMM")}
        </h4>
        <.button
          type="button"
          variant="ghost"
          size="small"
          phx-click="select_day"
          phx-value-date={Date.to_iso8601(@date)}
          phx-target={@target}
          aria-label={gettext("Show all months")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </.button>
      </div>
      <p :if={@blocks == []} class="text-sm text-grey-600">{gettext("No sessions on this day.")}</p>
      <div :if={@blocks != []} class="flex flex-col gap-1">
        <div class="relative h-3 rounded-sm bg-grey-100">
          <span
            :for={block <- @blocks}
            class={["absolute inset-y-0 rounded-sm", @colors[block.project_id]]}
            style={"left: #{(block.from - @axis_from) / @span * 100}%; width: #{(block.to - block.from) / @span * 100}%"}
          />
        </div>
        <div class="flex justify-between text-[10px] text-grey-500 tabular-nums">
          <span :for={tick <- @ticks}>{tick}:00</span>
        </div>
      </div>
      <ul :if={@blocks != []} class="flex flex-col divide-y divide-grey-100">
        <li
          :for={block <- @blocks}
          id={"work-day-session-#{block.id}"}
          class="grid grid-cols-[auto_1fr_auto_auto] items-center gap-x-3 py-2 text-sm"
        >
          <span class={["size-2.5 rounded-full", @colors[block.project_id]]} />
          <span class="min-w-0">
            <span class="block truncate text-grey-900">{block.title}</span>
            <span class="block text-xs text-grey-600">{block.project}</span>
          </span>
          <span class="text-grey-600 tabular-nums">{block.range}</span>
          <span class="w-10 text-right font-medium text-grey-900 tabular-nums">
            {hours(block.seconds)} h
          </span>
        </li>
      </ul>
    </section>
    """
  end

  defp month(date, by_day) do
    days =
      date
      |> Date.range(Date.end_of_month(date))
      |> Map.new(fn day ->
        {day, by_day |> Map.get(day, []) |> Enum.map(& &1.duration) |> Enum.sum()}
      end)

    weeks =
      date
      |> Date.beginning_of_week()
      |> Date.range(date |> Date.end_of_month() |> Date.end_of_week())
      |> Enum.chunk_every(7)
      |> Enum.map(fn dates ->
        cells =
          Enum.map(dates, fn day ->
            %{date: day, seconds: Map.get(days, day, 0), outside: not Map.has_key?(days, day)}
          end)

        %{dates: dates, cells: cells, seconds: cells |> Enum.map(& &1.seconds) |> Enum.sum()}
      end)

    %{date: date, weeks: weeks, seconds: days |> Map.values() |> Enum.sum()}
  end

  defp by_day(sessions), do: Enum.group_by(sessions, &local_date(&1.start_datetime))

  defp local_date(datetime), do: datetime |> DateTime.shift_zone!(@timezone) |> DateTime.to_date()

  # Projects with more hours in the shown period take the first colours.
  defp project_colors(sessions) do
    sessions
    |> Enum.group_by(& &1.project_id)
    |> Enum.sort_by(
      fn {_project_id, project_sessions} ->
        project_sessions |> Enum.map(& &1.duration) |> Enum.sum()
      end,
      :desc
    )
    |> Enum.with_index()
    |> Map.new(fn {{project_id, _sessions}, index} ->
      {project_id, Enum.at(@colors, index, List.last(@colors))}
    end)
  end

  defp intensity_styles(seconds) do
    cond do
      seconds == 0 -> "bg-grey-100 text-grey-500"
      seconds < 4 * 3600 -> "bg-teal-200 text-teal-900"
      seconds < 7 * 3600 -> "bg-teal-400 text-teal-950"
      seconds < 9 * 3600 -> "bg-teal-600 text-white"
      true -> "bg-teal-800 text-white"
    end
  end

  defp hours(seconds) do
    hours = seconds / 3600
    if hours == trunc(hours), do: trunc(hours), else: :erlang.float_to_binary(hours, decimals: 1)
  end
end
