defmodule FirmowidWeb.Timetracker.Components.Session do
  @moduledoc false
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Timetracker.Utilities.GroupedSessionForm
  alias FirmowidWeb.Timetracker.Views.Index

  attr :sessions, :list, required: true
  attr :active_projects, :list, required: true
  attr :projects_by_id, :map, required: true

  def render(assigns) do
    ~H"""
    <% parent_session = hd(@sessions) %>
    <% form_id = "edit-session-form-#{parent_session.id}" %>
    <.form
      :let={sessions_form}
      as={:sessions_form}
      id={form_id}
      for={GroupedSessionForm.from_sessions(@sessions)}
      phx-submit="validate_and_update_list_onsubmit"
      phx-change="validate_and_update_list_onchange"
      phx-auto-recover="ignore"
      class="flex w-full min-w-0 flex-row items-center py-1 pl-1"
    >
      <input :for={s <- @sessions} type="hidden" name="sessions_form[ids][]" value={s.id} />
      <input
        type="hidden"
        id={sessions_form[:project_id].id}
        name={sessions_form[:project_id].name}
        value={sessions_form[:project_id].value}
      />

      <div class="group mr-4 flex min-w-0 flex-1 flex-row items-center gap-1">
        <.hidden_input>
          <:input>
            <input
              id={sessions_form[:title].id}
              name={sessions_form[:title].name}
              value={sessions_form[:title].value}
              class={text_like_input_styles(["max-w-full", "truncate"])}
              style="field-sizing: content;"
              phx-debounce="300"
            />
          </:input>
        </.hidden_input>

        <span :if={length(@sessions) > 1} class="text-grey-600 line-clamp-1 shrink-0">
          | {length(@sessions)} sesji
        </span>

        <.button
          type="button"
          phx-click={JS.focus(to: "##{sessions_form[:title].id}")}
          variant="unstyled"
          class="opacity-0 transition group-hover:opacity-100 focus:outline-hidden"
        >
          <span class="sr-only">Edytuj tytuł</span>
        </.button>
      </div>

      <% select_id = "session-project-select-#{parent_session.id}" %>
      <.button
        id={"project-select-#{parent_session.id}"}
        type="button"
        phx-click={show_popover(select_id)}
        disabled={parent_session.lockdown}
        variant="unstyled"
        class="hover:bg-grey-200 text-darkGrey ml-auto min-w-0 cursor-pointer rounded border-none bg-transparent px-2 py-1 text-sm uppercase transition focus:ring-0 disabled:pointer-events-none"
      >
        {case Enum.find(@active_projects, &(&1.id == parent_session.project_id)) do
          nil -> "Select"
          project -> project.name
        end}
      </.button>

      <.popover
        placement="bottom-end"
        id={select_id}
        reference_id={"project-select-#{parent_session.id}"}
        class="bg-grey-50 border-grey-200 w-[230px] rounded-lg border"
      >
        <ul class="flex flex-col gap-1 overflow-auto p-1">
          <li
            :for={project <- @active_projects}
            class="cursor-pointer rounded px-2 py-1.5 text-sm transition hover:bg-orange-100 hover:text-orange-800"
            phx-click={
              JS.set_attribute(
                {"value", project.id},
                to: "##{sessions_form[:project_id].id}"
              )
              |> JS.dispatch("submit", to: "##{form_id}")
              |> hide_popover(select_id)
            }
          >
            {project.name}
          </li>
        </ul>
      </.popover>

      <% popover_id = "edit-sessions-popover-#{parent_session.id}" %>
      <% total_duration = @sessions |> Index.calculate_total_duration() %>
      <.button
        class="hover:bg-grey-200 ml-4 w-14 shrink-0 rounded-md py-1 text-center font-bold transition lg:ml-8"
        id={"session-timer-#{parent_session.id}"}
        type="button"
        phx-click={show_popover(popover_id)}
        phx-hook="Timer"
        data-start_time={DateTime.shift(DateTime.utc_now(), second: -1 * total_duration)}
        data-format="short"
        data-disabled={parent_session.end_datetime != nil}
        variant="unstyled"
      >
        {TimeFormatter.format_timer(total_duration)}
      </.button>

      <.popover
        id={popover_id}
        reference_id={form_id}
        placement="bottom-end"
        class="border-grey-200 space-y-6 rounded-lg border bg-white px-6 py-4 shadow-lg"
      >
        <div class="grid grid-cols-[repeat(5,auto)] gap-x-4 gap-y-3">
          <div class="text-grey-700 col-span-5 grid grid-cols-subgrid text-sm">
            <p class="col-start-2">Data</p>
            <p>Od</p>
            <p>Do</p>
          </div>
          <div class="col-span-5 grid grid-cols-subgrid items-center gap-y-4">
            <.inputs_for :let={session} field={sessions_form[:start_end_times]}>
              <.input type="hidden" field={session[:id]} />
              <%= if overnight_session?(session) do %>
                <p class="text-grey-600 line-clamp-1 text-sm font-semibold">
                  Sesja {session.index + 1}
                </p>
                <.input
                  type="date"
                  field={session[:date]}
                  input_class="border-grey-200 rounded-lg py-2 px-3"
                />
                <.input
                  type="time"
                  step="60"
                  field={session[:start_time]}
                  value={format_time(session[:start_time].value)}
                  input_class="border-grey-200 rounded-lg py-2 px-3"
                />
                <span class="text-grey-500 text-center">-</span>

                <span></span>
                <span></span>

                <.input
                  type="date"
                  field={session[:end_date]}
                  input_class="border-grey-200 rounded-lg py-2 px-3"
                />

                <span class="text-grey-500 text-center">-</span>

                <.input
                  type="time"
                  step="60"
                  field={session[:end_time]}
                  value={format_time(session[:end_time].value)}
                  input_class="border-grey-200 rounded-lg py-2 px-3"
                />

                <.button
                  type="button"
                  phx-click="collapse_overnight_session"
                  phx-value-id={session[:id].value}
                  variant="unstyled"
                >
                  <Lucideicons.trash_2 class="hover:text-darkGrey text-grey-500 transition-all" />
                </.button>
              <% else %>
                <p class="text-grey-600 line-clamp-1 text-sm font-semibold">
                  Sesja {session.index + 1}
                </p>
                <.input
                  type="date"
                  field={session[:date]}
                  input_class="border-grey-200 rounded-lg py-2 px-3"
                />
                <.input
                  type="time"
                  step="60"
                  field={session[:start_time]}
                  value={format_time(session[:start_time].value)}
                  input_class="border-grey-200 rounded-lg py-2 px-3"
                />
                <.input
                  type="time"
                  step="60"
                  field={session[:end_time]}
                  value={format_time(session[:end_time].value)}
                  input_class="border-grey-200 rounded-lg py-2 px-3"
                />
                <.button
                  type="button"
                  phx-click="delete_session"
                  phx-value-id={session[:id].value}
                  variant="unstyled"
                >
                  <Lucideicons.trash_2 class="hover:text-darkGrey text-grey-500 transition-all" />
                </.button>
              <% end %>
            </.inputs_for>
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <.button
            type="button"
            variant="outline"
            class="max-w-28 flex-1 text-sm"
            phx-click={hide_popover(popover_id)}
          >
            Anuluj
          </.button>
          <.button type="submit" class="max-w-28 flex-1 text-sm">
            Zapisz
          </.button>
        </div>
      </.popover>
    </.form>
    """
  end

  def format_time(nil), do: "trwa"

  def format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
  def format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M")

  def format_date(nil), do: nil
  def format_date(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()

  defp overnight_session?(session) do
    start_date = session[:date].value
    end_date = session[:end_date].value

    start_date && end_date &&
      Date.before?(start_date, end_date)
  end
end
