defmodule FirmowidWeb.Timetracker.Components.Session do
  @moduledoc false
  use FirmowidWeb, :html

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
      class="flex flex-row items-center pl-1 min-w-0 w-full py-1"
    >
      <input :for={s <- @sessions} type="hidden" name="sessions_form[ids][]" value={s.id} />
      <input
        type="hidden"
        id={sessions_form[:project_id].id}
        name={sessions_form[:project_id].name}
        value={sessions_form[:project_id].value}
      />

      <div class="flex flex-row items-center group min-w-0 flex-1 gap-1 mr-4">
        <input
          id={sessions_form[:title].id}
          name={sessions_form[:title].name}
          value={sessions_form[:title].value}
          class="border-none p-1 -ml-1 rounded read-only:bg-transparent hover:bg-grey-200 bg-grey-200 transition focus:ring-0 truncate min-w-0 max-w-full"
          style="field-sizing: content;"
          phx-click={JS.remove_attribute("readonly")}
          phx-blur={JS.set_attribute({"readonly", true})}
          phx-click-away={JS.set_attribute({"readonly", true})}
          phx-keydown={JS.set_attribute({"readonly", true})}
          phx-key="enter"
          phx-debounce="300"
          readonly
        />

        <span :if={length(@sessions) > 1} class="text-grey-600 line-clamp-1 shrink-0">
          | {length(@sessions)} sesji
        </span>

        <button
          type="button"
          phx-click={
            JS.remove_attribute("readonly", to: "##{sessions_form[:title].id}")
            |> JS.focus(to: "##{sessions_form[:title].id}")
          }
          class="opacity-0 group-hover:opacity-100 transition focus:outline-hidden"
        >
        </button>
      </div>

      <% select_id = "session-project-select-#{parent_session.id}" %>
      <button
        id={"project-select-#{parent_session.id}"}
        type="button"
        selecttarget={select_id}
        phx-click={show_popover(select_id)}
        disabled={parent_session.lockdown}
        class="text-sm text-darkGrey uppercase bg-transparent hover:bg-grey-200 transition py-1 px-2 rounded border-none focus:ring-0 disabled:pointer-events-none !bg-none cursor-pointer ml-auto min-w-0"
      >
        {case Enum.find(@active_projects, &(&1.id == parent_session.project_id)) do
          nil -> "Select"
          project -> project.name
        end}
      </button>

      <.popover
        placement="bottom-end"
        id={select_id}
        reference_id={"project-select-#{parent_session.id}"}
        class="bg-grey-50 border border-grey-200 w-[230px] rounded-lg  "
      >
        <ul class="overflow-auto p-1 flex flex-col gap-1">
          <li
            :for={project <- @active_projects}
            class="px-2 py-1.5 rounded text-sm cursor-pointer transition hover:bg-orange-100 hover:text-orange-800 "
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
      <button
        class="font-bold w-14 shrink-0 text-center hover:bg-grey-200 transition py-1 rounded-md ml-4 lg:ml-8"
        id={"session-timer-#{parent_session.id}"}
        type="button"
        popovertarget={popover_id}
        phx-click={show_popover(popover_id)}
        phx-hook="Timer"
        data-start_time={DateTime.shift(DateTime.utc_now(), second: -1 * total_duration)}
        data-format="short"
        data-disabled={parent_session.end_datetime != nil}
      >
        {TimeFormatter.format_timer(total_duration)}
      </button>

      <.popover
        id={popover_id}
        reference_id={form_id}
        placement="bottom-end"
        class="bg-white border border-grey-200 rounded-lg shadow-lg py-4 px-6 space-y-6"
      >
        <div class="grid grid-cols-[repeat(5,auto)] gap-y-3 gap-x-4">
          <div class="grid grid-cols-subgrid col-span-5 text-sm text-grey-700">
            <p class="col-start-2">Data</p>
            <p>Od</p>
            <p>Do</p>
          </div>
          <div class="grid grid-cols-subgrid col-span-5 gap-y-4 items-center">
            <.inputs_for :let={session} field={sessions_form[:start_end_times]}>
              <.input type="hidden" field={session[:id]} />
              <p class="text-sm text-grey-600 font-semibold line-clamp-1">
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
              <button
                type="button"
                phx-click="delete_session"
                phx-value-id={session[:id].value}
              >
                <Lucideicons.trash_2 class="hover:text-darkGrey text-grey-500 transition-all" />
              </button>
            </.inputs_for>
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <.button
            type="button"
            color="light_grey"
            variant="outline"
            class="text-sm flex-1 max-w-28"
            phx-click={hide_popover(popover_id)}
          >
            Anuluj
          </.button>
          <.button type="submit" color="orange" class="text-sm flex-1 max-w-28">
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
end
