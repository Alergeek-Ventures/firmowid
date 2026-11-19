defmodule FirmowidWeb.Timetracker.Components.Session do
  @moduledoc false
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.Tooltip
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.TimeFormatter
  alias FirmowidWeb.Timetracker.Utilities.GroupedSessionForm
  alias FirmowidWeb.Timetracker.Utilities.Navigation
  alias FirmowidWeb.Timetracker.Views.Index

  attr :sessions, :list, required: true
  attr :active_projects, :list, required: true
  attr :projects_by_id, :map, required: true

  attr :filter, :map,
    default: nil,
    doc: "the project and month the list is narrowed to; its rows leave out the project"

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :same_presence?,
        assigns.sessions |> Enum.uniq_by(& &1.is_remote) |> length() == 1
      )

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
      class={[
        "group/row relative flex w-full min-w-0 flex-row items-center border-b px-2 max-md:flex-wrap",
        if(@filter, do: "min-h-12 border-grey-200 py-2", else: "border-grey-100 py-3")
      ]}
    >
      <input :for={s <- @sessions} type="hidden" name="sessions_form[ids][]" value={s.id} />
      <input
        type="hidden"
        id={sessions_form[:project_id].id}
        name={sessions_form[:project_id].name}
        value={sessions_form[:project_id].value}
      />

      <%!-- Pulled left so the title's hover background starts at the row's edge, as in Figma. --%>
      <div class="group -ml-2 flex min-w-0 flex-1 flex-row items-center gap-[11px] max-md:basis-full">
        <.hidden_input>
          <:input>
            <%!-- In the filtered list a title stands for a whole task, so say that renaming moves all its sessions. --%>
            <.tooltip
              :if={@filter && length(@sessions) > 1}
              id={"task-rename-#{parent_session.id}"}
              text={
                ngettext(
                  "The change applies to the %{count} session of this task in %{month}",
                  "The change applies to all %{count} sessions of this task in %{month}",
                  length(@sessions),
                  month: Index.month_after_in(@filter.month)
                )
              }
              variant="hint"
              placement="top-start"
              class="max-w-full min-w-0"
            >
              <.title_input field={sessions_form[:title]} />
            </.tooltip>
            <.title_input :if={!(@filter && length(@sessions) > 1)} field={sessions_form[:title]} />
          </:input>
        </.hidden_input>

        <span
          :if={length(@sessions) > 1}
          class="shrink-0 text-sm/[1.4] whitespace-nowrap text-grey-500"
        >
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
      <%!-- The row's items are spaced by margins, as the popovers' focus wraps would take a gap. --%>
      <%!-- The column keeps Figma's width, the hover background only the name's. --%>
      <span
        :if={!@filter}
        class="-mr-2 ml-[3px] flex min-w-0 justify-end max-md:-ml-2 xl:w-39 xl:shrink-0"
      >
        <.button
          id={"project-select-#{parent_session.id}"}
          type="button"
          phx-click={show_popover(select_id)}
          disabled={parent_session.lockdown}
          variant="unstyled"
          class={[
            "block max-w-full min-w-0 cursor-pointer truncate border-none text-xs/7 font-medium text-grey-500 uppercase focus:ring-0 disabled:pointer-events-none",
            row_control_styles()
          ]}
        >
          {case Enum.find(@active_projects, &(&1.id == parent_session.project_id)) do
            nil -> gettext("Select")
            project -> project.name
          end}
        </.button>
      </span>

      <.popover
        :if={!@filter}
        placement="bottom-end"
        id={select_id}
        reference_id={"project-select-#{parent_session.id}"}
        class={[
          "w-[230px] origin-top-right rounded-lg border border-grey-200 bg-grey-50",
          dropdown_styles()
        ]}
      >
        <ul class="flex flex-col gap-1 overflow-auto p-1">
          <li
            :for={project <- @active_projects}
            class={dropdown_item_styles()}
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

      <.work_mode :if={!@filter} sessions={@sessions} />

      <% popover_id = "edit-sessions-popover-#{parent_session.id}" %>
      <% total_duration = @sessions |> Index.calculate_total_duration() %>
      <span class={[
        "-mr-2 flex w-18 shrink-0 justify-end max-md:ml-auto",
        if(@filter, do: "ml-1", else: "ml-[3px]")
      ]}>
        <.button
          class={["block text-sm/7 font-semibold text-grey-900 tabular-nums", row_control_styles()]}
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
      </span>

      <%!-- Sits in the list's right padding, so the row keeps its width. Desktop only. --%>
      <% session_month = Index.session_month(parent_session) %>
      <% filter_label =
        gettext("Show %{project} sessions in %{month}",
          project: @projects_by_id[parent_session.project_id].name,
          month: Index.month_after_in(session_month)
        ) %>
      <.tooltip
        :if={!@filter}
        id={"session-filter-#{parent_session.id}"}
        text={filter_label}
        variant="hint"
        placement="top-end"
        class="absolute top-1/2 -right-7 -translate-y-1/2 opacity-0 transition group-hover/row:opacity-100 focus-within:opacity-100 max-md:hidden"
      >
        <.link
          patch={Navigation.project_sessions_path(parent_session.project_id, session_month)}
          kind="unstyled"
          class="group/filter rounded p-1 text-grey-600 transition-colors hover:text-grey-900 focus-visible:text-grey-900"
          aria-label={filter_label}
        >
          <%!-- On hover the funnel darkens and fills in, with no background behind it. --%>
          <Lucideicons.funnel
            class="size-4 transition-colors group-hover/filter:fill-current group-focus-visible/filter:fill-current"
            aria-hidden="true"
          />
        </.link>
      </.tooltip>

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

        <div class="flex items-center justify-end gap-3">
          <%!-- On phones the popover overflows the left edge, so keep the choice beside the buttons. --%>
          <%!-- A task mixing office and remote sessions keeps each session's own choice. --%>
          <div :if={@same_presence?} class="flex gap-1 md:mr-auto">
            <label
              :for={
                {value, label} <- [
                  {false, pgettext("presence", "in the office")},
                  {true, pgettext("presence", "remotely")}
                ]
              }
              class="cursor-pointer"
            >
              <input
                type="radio"
                name={sessions_form[:is_remote].name}
                value={to_string(value)}
                checked={sessions_form[:is_remote].value == value}
                class="peer sr-only"
              />
              <span class="inline-flex h-8 items-center gap-1.5 rounded-full px-3 text-sm font-medium whitespace-nowrap text-grey-700 transition-colors peer-checked:bg-grey-700 peer-checked:text-white peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-(--focus-ring) hover:bg-grey-200 peer-checked:hover:bg-grey-700">
                <Lucideicons.building_2 :if={!value} class="size-4" aria-hidden="true" />
                <Lucideicons.house :if={value} class="size-4" aria-hidden="true" />
                {label}
              </span>
            </label>
          </div>
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

  attr :sessions, :list, required: true

  # Where the row's sessions were worked: a house when remote, a lighter house
  # with a tooltip when only some were, nothing for the office. A click opens a
  # list that switches all the row's sessions at once.
  defp work_mode(assigns) do
    parent_session = hd(assigns.sessions)
    remote_count = Enum.count(assigns.sessions, & &1.is_remote)

    mode =
      cond do
        remote_count == 0 -> :office
        remote_count == length(assigns.sessions) -> :remote
        true -> :mixed
      end

    assigns =
      assign(assigns,
        id: parent_session.id,
        locked?: parent_session.lockdown,
        mode: mode,
        remote_count: remote_count
      )

    ~H"""
    <div class="group/mode-slot ml-[11px] flex h-6 w-10 shrink-0 items-center">
      <.tooltip
        :if={@mode == :mixed}
        id={"session-work-mode-hint-#{@id}"}
        text={
          gettext("%{remote} of %{count} sessions remotely",
            remote: @remote_count,
            count: length(@sessions)
          )
        }
        variant="hint"
        placement="top"
      >
        <.work_mode_control id={@id} mode={@mode} locked?={@locked?} sessions={@sessions} />
      </.tooltip>
      <.work_mode_control
        :if={@mode != :mixed}
        id={@id}
        mode={@mode}
        locked?={@locked?}
        sessions={@sessions}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :mode, :atom, required: true
  attr :locked?, :boolean, required: true
  attr :sessions, :list, required: true

  defp work_mode_control(%{locked?: true} = assigns) do
    ~H"""
    <span class="flex h-6 items-center pl-1">
      <.work_mode_icon mode={@mode} class={work_mode_icon_styles(@mode)} />
    </span>
    """
  end

  defp work_mode_control(assigns) do
    ~H"""
    <% list_id = "session-work-mode-list-#{@id}" %>
    <.button
      id={"session-work-mode-#{@id}"}
      type="button"
      variant="unstyled"
      phx-click={show_popover(list_id)}
      aria-label={
        gettext("Work mode: %{mode}",
          mode:
            case @mode do
              :office -> pgettext("workplace", "In the office")
              :remote -> pgettext("workplace", "Remotely")
              :mixed -> pgettext("workplace", "Partly remote")
            end
        )
      }
      class={[
        "group/mode -ml-1 flex cursor-pointer items-center group-has-[[role=dialog][style*='display:_block']]/mode-slot:bg-grey-100",
        row_control_styles()
      ]}
    >
      <.work_mode_icon
        mode={@mode}
        class={[
          "transition group-hover/mode:opacity-100 group-focus-visible/mode:opacity-100 group-has-[[role=dialog][style*='display:_block']]/mode-slot:opacity-100",
          work_mode_icon_styles(@mode)
        ]}
      />
    </.button>

    <.popover
      id={list_id}
      reference_id={"session-work-mode-#{@id}"}
      placement="bottom-end"
      class={["w-40 origin-top-right rounded-lg border border-grey-200 bg-grey-50", dropdown_styles()]}
    >
      <ul class="flex flex-col gap-1 p-1">
        <li :for={{remote?, label} <- work_mode_options()}>
          <.button
            type="button"
            variant="unstyled"
            phx-click={
              JS.push("set_work_mode",
                value: %{ids: Enum.map(@sessions, & &1.id), is_remote: remote?}
              )
              |> hide_popover(list_id)
            }
            class={["w-full text-left", dropdown_item_styles()]}
          >
            {label}
          </.button>
        </li>
      </ul>
    </.popover>
    """
  end

  defp work_mode_options do
    [{false, pgettext("workplace", "In the office")}, {true, pgettext("workplace", "Remotely")}]
  end

  attr :mode, :atom, required: true
  attr :class, :any, default: nil

  defp work_mode_icon(%{mode: :office} = assigns) do
    ~H"""
    <Lucideicons.building_2 class={["size-4 shrink-0", @class]} aria-hidden="true" />
    """
  end

  defp work_mode_icon(assigns) do
    ~H"""
    <Lucideicons.house class={["size-4 shrink-0", @class]} aria-hidden="true" />
    """
  end

  # At rest the office shows nothing, a remote row a grey house and a mixed one
  # a lighter house. Hovering the control shows its icon on a grey background.
  defp work_mode_icon_styles(:office), do: "text-grey-500 opacity-0"
  defp work_mode_icon_styles(:remote), do: "text-grey-500"
  defp work_mode_icon_styles(:mixed), do: "text-grey-300"

  # The hover shared by the row's controls (title, project, work mode and
  # time): a light grey background 28 px high with 8 px on the sides, as wide
  # as the content. The negative margin keeps the row's height.
  defp row_control_styles do
    "-my-1 h-7 rounded px-2 transition-colors hover:bg-grey-100 focus-visible:bg-grey-100"
  end

  @doc """
  Entrance of the time tracker's dropdowns (project, work mode): they grow and
  fade in each time they open, whatever opens them. The caller sets the origin.
  """
  @spec dropdown_styles() :: String.t()
  def dropdown_styles do
    "transition-[opacity,scale] duration-150 ease-out starting:scale-95 starting:opacity-0 motion-reduce:transition-none"
  end

  @doc "An option in the time tracker's dropdowns (project, work mode)."
  @spec dropdown_item_styles() :: String.t()
  def dropdown_item_styles do
    "cursor-pointer rounded px-2 py-1.5 text-sm transition hover:bg-grey-200 hover:text-grey-800"
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp title_input(assigns) do
    ~H"""
    <input
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class={
        text_like_input_styles([
          "-my-1! ml-0! h-7 max-w-full truncate px-2! py-0! text-sm/7 text-grey-900 hover:bg-grey-100! focus:bg-grey-100! focus-visible:outline-none"
        ])
      }
      style="field-sizing: content;"
      phx-debounce="300"
    />
    """
  end

  def format_time(nil), do: gettext("ongoing")

  def format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
  def format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M")

  defp overnight_session?(session) do
    start_date = session[:date].value
    end_date = session[:end_date].value

    start_date && end_date &&
      Date.before?(start_date, end_date)
  end
end
