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
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.Rendered

  attr :sessions, :list, required: true
  attr :active_projects, :list, required: true
  attr :projects_by_id, :map, required: true

  attr :filter, :map,
    default: nil,
    doc: "the project and month the list is narrowed to; its rows leave out the project"

  attr :highlighted, :boolean,
    default: false,
    doc: "lights the row up for a moment and scrolls to it, for a task a link points at"

  def render(assigns) do
    ~H"""
    <% parent_session = hd(@sessions) %>
    <% form_id = "edit-session-form-#{parent_session.id}" %>
    <% popover_id = "edit-sessions-popover-#{parent_session.id}" %>
    <.form
      :let={sessions_form}
      as={:sessions_form}
      id={form_id}
      for={GroupedSessionForm.from_sessions(@sessions)}
      phx-submit={JS.push("validate_and_update_list_onsubmit") |> hide_popover(popover_id)}
      phx-change="validate_and_update_list_onchange"
      phx-auto-recover="ignore"
      class={
        [
          # Figma "Sesja · wiersz / mobile": the title over two lines, the project, session count
          # and work mode below it, the time on the right across both. The popovers' empty
          # focus wraps share the first cell instead of opening a row.
          "group/row relative flex w-full min-w-0 flex-row items-center border-b px-2 max-md:grid max-md:grid-cols-[auto_auto_minmax(0,1fr)_auto] max-md:gap-y-1 max-md:*:[[phx-hook$=FocusWrap]]:col-start-1 max-md:*:[[phx-hook$=FocusWrap]]:row-start-1",
          if(@filter, do: "min-h-12 border-grey-200 py-2", else: "border-grey-100 py-3"),
          @highlighted &&
            "animate-[t-row-highlight_2.4s_ease-out] rounded-sm outline -outline-offset-1 outline-transparent motion-reduce:animate-none"
        ]
      }
      phx-hook={@highlighted && "ScrollIntoView"}
    >
      <input :for={s <- @sessions} type="hidden" name="sessions_form[ids][]" value={s.id} />
      <input
        type="hidden"
        id={sessions_form[:project_id].id}
        name={sessions_form[:project_id].name}
        value={sessions_form[:project_id].value}
      />

      <%!-- Pulled left so the title's hover background starts at the row's edge, as in Figma. --%>
      <div class="group -ml-2 flex min-w-0 flex-1 flex-row items-center gap-[11px] max-md:contents">
        <%!-- On phones the title shows as text that wraps; the field lies over it and shows up
        only while it is being edited, as an input keeps to one line. --%>
        <div class="group/title contents max-md:relative max-md:col-span-3 max-md:col-start-1 max-md:row-start-1 max-md:block max-md:min-w-0">
          <span
            aria-hidden="true"
            class="hidden text-sm/[1.4] wrap-break-word text-grey-900 group-focus-within/title:invisible max-md:line-clamp-2"
          >
            {sessions_form[:title].value}
          </span>
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
                class="max-w-full min-w-0 max-md:static"
              >
                <.title_input field={sessions_form[:title]} />
              </.tooltip>
              <.title_input :if={!(@filter && length(@sessions) > 1)} field={sessions_form[:title]} />
            </:input>
          </.hidden_input>
        </div>

        <span
          :if={length(@sessions) > 1}
          class="shrink-0 text-sm/[1.4] whitespace-nowrap text-grey-500 max-md:col-start-2 max-md:row-start-2 max-md:ml-2"
        >
          | {ngettext("%{count} session", "%{count} sessions", length(@sessions))}
        </span>

        <.button
          type="button"
          phx-click={JS.focus(to: "##{sessions_form[:title].id}")}
          variant="unstyled"
          class="opacity-0 transition group-hover:opacity-100 focus:outline-hidden max-md:hidden"
        >
          <span class="sr-only">{gettext("Edit title")}</span>
        </.button>
      </div>

      <% select_id = "session-project-select-#{parent_session.id}" %>
      <%!-- The row's items are spaced by margins, as the popovers' focus wraps would take a gap. --%>
      <%!-- The column keeps Figma's width, the hover background only the name's. --%>
      <span
        :if={!@filter}
        class="-mr-2 ml-[3px] flex min-w-0 justify-end max-md:col-start-1 max-md:row-start-2 max-md:-ml-2 max-md:justify-start xl:w-39 xl:shrink-0"
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
        data-offset="4"
        class={["origin-top-right", dropdown_panel_styles()]}
      >
        <ul
          id={"session-project-options-#{parent_session.id}"}
          role="listbox"
          aria-label={gettext("Project")}
          phx-hook="ListboxKeys"
          class="flex flex-col overflow-auto"
        >
          <li :for={project <- @active_projects} role="none">
            <.dropdown_option
              selected={project.id == parent_session.project_id}
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
            </.dropdown_option>
          </li>
        </ul>
      </.popover>

      <.work_mode :if={!@filter} sessions={@sessions} />

      <% total_duration = @sessions |> Index.calculate_total_duration() %>
      <span class={[
        "-mr-2 flex w-18 shrink-0 justify-end max-md:col-start-4 max-md:row-span-2 max-md:row-start-1 max-md:ml-3 max-md:w-auto",
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
          <% label = TimeFormatter.format_timer(total_duration) %>
          <%!-- Running sessions get their text from the Timer hook. A finished one
          pops in the digits a save changed. --%>
          <%= if parent_session.end_datetime do %>
            <span
              id={"session-duration-#{parent_session.id}"}
              class="group/digits inline-flex"
              data-value={label}
              data-changed-only
              phx-hook="NumberPopIn"
            >
              <span
                :for={digit <- String.graphemes(label)}
                class="inline-block will-change-[transform,opacity,filter] group-data-animating/digits:data-changed:animate-[t-digit-pop-in_var(--digit-dur)_var(--digit-ease)_both] motion-reduce:animate-none!"
              >
                {digit}
              </span>
            </span>
          <% else %>
            {label}
          <% end %>
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
          <.figma_icon
            name="filter"
            class="size-4 transition-colors group-hover/filter:fill-current group-focus-visible/filter:fill-current"
          />
        </.link>
      </.tooltip>

      <% single? = length(@sessions) == 1 %>
      <.popover
        id={popover_id}
        reference_id={form_id}
        placement="bottom-end"
        class={[
          "origin-top-right space-y-8 rounded border border-grey-200 bg-white px-6 py-4 shadow-small",
          dropdown_styles()
        ]}
      >
        <%!-- One session sets its work mode below; several get a column each. --%>
        <div class={[
          "grid gap-x-4",
          if(single?,
            do: "grid-cols-[58px_136px_109px_109px_24px]",
            else: "grid-cols-[58px_136px_109px_109px_120px_24px]"
          )
        ]}>
          <div class="col-span-full grid grid-cols-subgrid text-sm/[1.55] text-grey-500">
            <p class="col-start-2 px-2">{gettext("Date")}</p>
            <p class="px-2">{pgettext("time range column", "From")}</p>
            <p class="px-2">{pgettext("time range column", "To")}</p>
            <p :if={!single?} class="px-2">{pgettext("session column", "Place")}</p>
          </div>
          <div class="col-span-full mt-2 grid grid-cols-subgrid items-center gap-y-6">
            <.inputs_for :let={session} field={sessions_form[:start_end_times]}>
              <.input type="hidden" field={session[:id]} />
              <%= if overnight_session?(session) do %>
                <div class="col-span-full grid grid-cols-subgrid items-center gap-y-2">
                  <p class={session_label_styles()}>
                    {gettext("Session %{number}", number: session.index + 1)}
                  </p>
                  <.date_field field={session[:date]} />
                  <.time_field
                    field={session[:start_time]}
                    value={format_time(session[:start_time].value)}
                  />
                  <.time_field name="time_placeholder" value="" readonly disabled />
                  <.workplace_select :if={!single?} field={session[:is_remote]} />
                  <div />

                  <div />
                  <.date_field field={session[:end_date]} />
                  <.time_field name="time_placeholder" value="" readonly disabled />
                  <.time_field
                    field={session[:end_time]}
                    value={format_time(session[:end_time].value)}
                  />
                  <div :if={!single?} />
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
                    <.figma_icon name="trash" class={trash_icon_styles()} />
                  </.button>
                </div>
              <% else %>
                <p class={session_label_styles()}>
                  {gettext("Session %{number}", number: session.index + 1)}
                </p>
                <.date_field field={session[:date]} />
                <.time_field
                  field={session[:start_time]}
                  value={format_time(session[:start_time].value)}
                />
                <.time_field
                  field={session[:end_time]}
                  value={format_time(session[:end_time].value)}
                />
                <.workplace_select :if={!single?} field={session[:is_remote]} />
                <.button
                  type="button"
                  phx-click="delete_session"
                  phx-value-id={session[:id].value}
                  variant="unstyled"
                  aria-label={gettext("Delete session")}
                >
                  <.figma_icon name="trash" class={trash_icon_styles()} />
                </.button>
              <% end %>
            </.inputs_for>
          </div>
        </div>

        <div class="flex items-center justify-end gap-3">
          <%!-- On phones the popover overflows the left edge, so keep the choice beside the buttons. --%>
          <.workplace_switch
            :if={single?}
            name={sessions_form[:start_end_times].name <> "[0][is_remote]"}
            remote={parent_session.is_remote}
          />
          <.button
            type="button"
            variant="outline"
            size="small"
            class="rounded! text-grey-900"
            phx-click={hide_popover(popover_id)}
          >
            {gettext("Cancel")}
          </.button>
          <.button type="submit" variant="special" size="small" class="rounded!">
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
    <div class="group/mode-slot ml-[11px] flex h-6 w-10 shrink-0 items-center max-md:col-start-3 max-md:row-start-2 max-md:ml-1 max-md:w-auto">
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
      data-offset="4"
      class={["origin-top-right", dropdown_panel_styles()]}
    >
      <ul
        id={"session-work-mode-options-#{@id}"}
        role="listbox"
        aria-label={gettext("Workplace")}
        phx-hook="ListboxKeys"
        class="flex flex-col"
      >
        <li :for={{remote?, label} <- work_mode_options()} role="none">
          <.dropdown_option
            selected={@mode == if(remote?, do: :remote, else: :office)}
            phx-click={
              JS.push("set_work_mode",
                value: %{ids: Enum.map(@sessions, & &1.id), is_remote: remote?}
              )
              |> hide_popover(list_id)
            }
          >
            {label}
          </.dropdown_option>
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
    <.figma_icon name="company" class={["size-4", @class]} />
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
  Entrance of the session edit popover: it grows and fades in each time it opens, whatever
  opens it, like the dropdowns (`dropdown_panel_styles/0`). The caller sets the origin.
  """
  @spec dropdown_styles() :: String.t()
  def dropdown_styles do
    "transition-[opacity,scale] duration-150 ease-out starting:scale-95 starting:opacity-0 motion-reduce:transition-none"
  end

  @doc """
  Date field of the time tracker's session forms, with the calendar icon from
  Figma. Chromium's own picker button stays, invisible, under the icon so a click
  still opens the picker; Firefox's is cut off by the frame (`time_field_styles/1`).
  """
  @spec date_field(map()) :: Rendered.t()
  attr :field, FormField, required: true
  attr :invalid, :boolean, default: false, doc: "Marks the field with a brick border."

  def date_field(assigns) do
    ~H"""
    <div class="relative">
      <.input
        type="date"
        field={@field}
        class={field_frame_styles(@invalid)}
        input_class={[
          "text-grey-700! [&::-webkit-calendar-picker-indicator]:opacity-0",
          time_field_styles()
        ]}
      />
      <.figma_icon
        name="calendar"
        class="pointer-events-none absolute top-[9px] right-3 size-4 text-grey-700"
      />
    </div>
    """
  end

  @doc "Time field of the time tracker's session forms: centred, without a clock button."
  @spec time_field(map()) :: Rendered.t()
  attr :field, FormField, default: nil
  attr :value, :string, required: true
  attr :invalid, :boolean, default: false, doc: "Marks the field with a brick border."
  attr :rest, :global, include: ~w(name disabled readonly)

  def time_field(assigns) do
    ~H"""
    <.input
      type="time"
      step="60"
      field={@field}
      value={@value}
      class={field_frame_styles(@invalid)}
      input_class={[
        "text-center text-black! disabled:text-grey-400! [&::-webkit-calendar-picker-indicator]:hidden [&::-webkit-datetime-edit]:flex [&::-webkit-datetime-edit]:justify-center supports-[-moz-appearance:none]:pl-1!",
        time_field_styles()
      ]}
      {@rest}
    />
    """
  end

  # The frame carries the border and clips the field: Chromium hides its picker
  # buttons through a pseudo-element, Firefox offers none, so there the field is
  # widened by its button and the frame cuts the button off. The time then gets a
  # smaller left padding to stay centred.
  defp field_frame_styles(invalid?) do
    [
      "overflow-hidden rounded border bg-white",
      if(invalid?, do: "border-brick-500", else: "border-grey-200 focus-within:border-grey-700")
    ]
  end

  defp time_field_styles do
    "block h-8 rounded-none! border-0! bg-transparent! text-base/[1.35]! supports-[-moz-appearance:none]:w-[calc(100%+36px)]!"
  end

  attr :field, FormField, required: true

  # Where one of several edited sessions was worked. The option only changes the
  # hidden input; the label follows its value through CSS, as the server renders
  # the form again only after saving.
  defp workplace_select(assigns) do
    assigns = assign(assigns, :list_id, "#{assigns.field.id}-options")

    ~H"""
    <div class="group/place relative" phx-click-away={JS.hide(to: "##{@list_id}")}>
      <input type="hidden" id={@field.id} name={@field.name} value={to_string(@field.value)} />
      <.button
        id={"#{@field.id}-button"}
        type="button"
        variant="unstyled"
        aria-haspopup="listbox"
        phx-click={
          JS.toggle(to: "##{@list_id}", display: "flex") |> JS.focus_first(to: "##{@list_id}")
        }
        class="flex h-[34px] w-full cursor-pointer items-center gap-2.5 rounded border border-grey-200 bg-grey-50 px-3 text-left text-base/[1.35] text-black focus:border-grey-700 focus:outline-hidden"
      >
        <span class="min-w-0 flex-1 truncate group-has-[input[value=true]]/place:hidden">
          {pgettext("workplace", "In the office")}
        </span>
        <span class="hidden min-w-0 flex-1 truncate group-has-[input[value=true]]/place:block">
          {pgettext("workplace", "Remotely")}
        </span>
        <.figma_icon name="chevron_down" class="size-4 text-grey-700" />
      </.button>
      <ul
        id={@list_id}
        role="listbox"
        aria-label={gettext("Workplace")}
        phx-hook="ListboxKeys"
        class={[
          "absolute inset-x-0 top-full z-50 mt-1 hidden origin-top flex-col",
          dropdown_panel_styles()
        ]}
      >
        <li :for={{remote?, label} <- work_mode_options()} role="none">
          <%!-- The pick moves the check itself, as the server renders the form again
          only after saving. --%>
          <.dropdown_option
            selected={to_string(@field.value) == to_string(remote?)}
            phx-keydown={JS.hide(to: "##{@list_id}") |> JS.focus(to: "##{@field.id}-button")}
            phx-key="escape"
            phx-click={
              JS.set_attribute({"value", to_string(remote?)}, to: "##{@field.id}")
              |> JS.set_attribute({"aria-selected", "false"}, to: "##{@list_id} [role=option]")
              |> JS.set_attribute({"aria-selected", "true"})
              |> JS.hide(to: "##{@list_id}")
              |> JS.focus(to: "##{@field.id}-button")
            }
          >
            {label}
          </.dropdown_option>
        </li>
      </ul>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :remote, :boolean, required: true

  # Where a single edited session was worked, styled like the switch in the inbox.
  defp workplace_switch(assigns) do
    ~H"""
    <div
      role="radiogroup"
      aria-label={gettext("Workplace")}
      class="mr-auto flex items-center gap-0.5 rounded-sm bg-grey-100 p-0.5"
    >
      <label :for={{remote?, label} <- work_mode_options()} class="cursor-pointer">
        <input
          type="radio"
          name={@name}
          value={to_string(remote?)}
          checked={@remote == remote?}
          class="peer sr-only"
        />
        <span class="flex items-center rounded-[3px] px-2.5 py-1 text-sm/[normal] font-medium whitespace-nowrap text-grey-600 transition-colors peer-checked:bg-white peer-checked:text-black peer-checked:shadow-[0_1px_2px_0_rgb(0_0_0/0.08)] peer-focus-visible:outline-2 peer-focus-visible:outline-(--focus-ring) hover:text-grey-900">
          {label}
        </span>
      </label>
    </div>
    """
  end

  defp session_label_styles, do: "line-clamp-1 text-sm font-medium text-grey-700"

  defp trash_icon_styles, do: "size-6 text-grey-500 transition-colors hover:text-grey-700"

  attr :field, FormField, required: true

  defp title_input(assigns) do
    ~H"""
    <input
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class={
        text_like_input_styles([
          "-my-1! ml-0! h-7 max-w-full truncate px-2! py-0! text-sm/7 text-grey-900 hover:bg-grey-100! focus:bg-grey-100! focus-visible:outline-none",
          "max-md:absolute max-md:inset-y-0 max-md:-left-2 max-md:my-0! max-md:h-full max-md:w-[calc(100%+0.5rem)] max-md:max-w-none max-md:opacity-0 max-md:focus:opacity-100"
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
