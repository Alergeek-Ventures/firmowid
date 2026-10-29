defmodule FirmowidWeb.Timetracker.Components.Session do
  @moduledoc false
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
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
      class="flex w-full min-w-0 flex-row items-center py-1 pl-1 max-md:flex-wrap"
    >
      <input :for={s <- @sessions} type="hidden" name="sessions_form[ids][]" value={s.id} />
      <input
        type="hidden"
        id={sessions_form[:project_id].id}
        name={sessions_form[:project_id].name}
        value={sessions_form[:project_id].value}
      />

      <div class="group mr-4 flex min-w-0 flex-1 flex-row items-center gap-1 max-md:mr-0 max-md:basis-full">
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

        <span :if={length(@sessions) > 1} class="line-clamp-1 shrink-0 text-grey-600">
          | {ngettext("%{count} session", "%{count} sessions", length(@sessions))}
        </span>

        <.button
          type="button"
          phx-click={JS.focus(to: "##{sessions_form[:title].id}")}
          variant="unstyled"
          class="opacity-0 transition group-hover:opacity-100 focus:outline-hidden"
        >
          <span class="sr-only">{gettext("Edit title")}</span>
        </.button>
      </div>

      <% select_id = "session-project-select-#{parent_session.id}" %>
      <.button
        id={"project-select-#{parent_session.id}"}
        type="button"
        phx-click={show_popover(select_id)}
        disabled={parent_session.lockdown}
        variant="unstyled"
        class="ml-auto min-w-0 cursor-pointer rounded border-none bg-transparent px-2 py-1 text-sm text-grey-700 uppercase transition hover:bg-grey-200 focus:ring-0 disabled:pointer-events-none max-md:ml-0"
      >
        {case Enum.find(@active_projects, &(&1.id == parent_session.project_id)) do
          nil -> gettext("Select")
          project -> project.name
        end}
      </.button>

      <.popover
        placement="bottom-end"
        id={select_id}
        reference_id={"project-select-#{parent_session.id}"}
        class="w-[230px] rounded-lg border border-grey-200 bg-grey-50"
      >
        <ul class="flex flex-col gap-1 overflow-auto p-1">
          <li
            :for={project <- @active_projects}
            class="cursor-pointer rounded px-2 py-1.5 text-sm transition hover:bg-rust-100 hover:text-rust-800"
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
        class="ml-4 w-14 shrink-0 rounded-md py-1 text-center font-bold transition hover:bg-grey-200 max-md:ml-auto lg:ml-8"
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
        class="space-y-6 rounded-lg border border-grey-200 bg-white px-6 py-4 shadow-lg"
      >
        <div class="grid grid-cols-[repeat(5,auto)] gap-x-4 gap-y-3">
          <div class="col-span-5 grid grid-cols-subgrid text-sm text-grey-500">
            <p class="col-start-2 px-2">{gettext("Date")}</p>
            <p class="px-2">{pgettext("time range column", "From")}</p>
            <p class="px-2">{pgettext("time range column", "To")}</p>
          </div>
          <div class="col-span-5 grid grid-cols-subgrid items-center gap-y-4">
            <.inputs_for :let={session} field={sessions_form[:start_end_times]}>
              <.input type="hidden" field={session[:id]} />
              <%= if overnight_session?(session) do %>
                <div class="col-span-5 grid grid-cols-subgrid items-center gap-y-2">
                  <p class="line-clamp-1 text-sm text-grey-500">
                    {gettext("Session %{number}", number: session.index + 1)}
                  </p>
                  <.input
                    type="date"
                    field={session[:date]}
                  />
                  <.input
                    type="time"
                    step="60"
                    field={session[:start_time]}
                    value={format_time(session[:start_time].value)}
                  />

                  <.input
                    type="time"
                    name="time_placeholder"
                    value=""
                    readonly
                    disabled
                  />

                  <div />
                  <div />

                  <.input
                    type="date"
                    field={session[:end_date]}
                  />

                  <.input
                    type="time"
                    name="time_placeholder"
                    value=""
                    readonly
                    disabled
                  />

                  <.input
                    type="time"
                    step="60"
                    field={session[:end_time]}
                    value={format_time(session[:end_time].value)}
                  />

                  <.button
                    type="button"
                    phx-click="collapse_overnight_session"
                    phx-value-id={session[:id].value}
                    data-confirm={
                      gettext(
                        "Shorten the overnight session to one day? The time after midnight will be removed and cannot be restored."
                      )
                    }
                    variant="unstyled"
                    aria-label={gettext("Shorten session to one day")}
                  >
                    <Lucideicons.trash_2 class="text-grey-500 transition-all hover:text-grey-700" />
                  </.button>
                </div>
              <% else %>
                <p class="line-clamp-1 text-sm text-grey-500">
                  {gettext("Session %{number}", number: session.index + 1)}
                </p>
                <.input
                  type="date"
                  field={session[:date]}
                />
                <.input
                  type="time"
                  step="60"
                  field={session[:start_time]}
                  value={format_time(session[:start_time].value)}
                />
                <.input
                  type="time"
                  step="60"
                  field={session[:end_time]}
                  value={format_time(session[:end_time].value)}
                />
                <.button
                  type="button"
                  phx-click="delete_session"
                  phx-value-id={session[:id].value}
                  variant="unstyled"
                  aria-label={gettext("Delete session")}
                >
                  <Lucideicons.trash_2 class="text-grey-500 transition-all hover:text-grey-700" />
                </.button>
              <% end %>
            </.inputs_for>
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <.button
            type="button"
            variant="outline"
            class="text-sm"
            size="small"
            phx-click={hide_popover(popover_id)}
          >
            {gettext("Cancel")}
          </.button>
          <.button type="submit" class="text-sm" size="small">
            {gettext("Save")}
          </.button>
        </div>
      </.popover>
    </.form>
    """
  end

  def format_time(nil), do: gettext("ongoing")

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
