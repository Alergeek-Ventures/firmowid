defmodule FirmowidWeb.Timetracker.Components.Overlap do
  @moduledoc """
  Display components for the overlap confirmation modal in the timetracker.

  Renders the session being saved, then a row for each session it changes, with the old times
  struck through beside the new ones and a badge for the change (shortened, deleted, split).
  """
  use FirmowidWeb, :html

  # ── Session in question ──────────────────────────────────────────────

  attr :title, :string, required: true
  attr :project, :any, default: nil
  attr :start_datetime, :any, required: true
  attr :end_datetime, :any, required: true
  attr :date, :any, required: true
  attr :timezone, :string, required: true
  attr :edited, :boolean, default: false, doc: "the running session with edited times"

  @doc "The session being saved, on grey-100: a new one, or the running one being edited."
  def new_session_card(assigns) do
    ~H"""
    <section class="flex flex-col gap-1">
      <h3 class="text-caps-sm font-medium text-grey-500 uppercase">
        {if @edited,
          do: pgettext("session overlap", "Current session"),
          else: gettext("New session")}
      </h3>
      <div class="flex flex-col gap-1 rounded-sm bg-grey-100 p-2">
        <.session_heading title={@title} project={@project} />
        <p class="text-sm/[1.4] text-grey-600 tabular-nums">
          {format_date_local(@date, @timezone)}, {format_datetime_local(@start_datetime, @timezone)} – {format_datetime_local(
            @end_datetime,
            @timezone
          )}
        </p>
      </div>
    </section>
    """
  end

  # ── Affected session ─────────────────────────────────────────────────

  attr :action, :any, required: true
  attr :timezone, :string, required: true
  attr :projects_by_id, :map, required: true
  attr :edited, :boolean, default: false

  @doc """
  Figma "Nakładanie · zmiana sesji": in a grey-100 outline, what happens to the session as a badge, its
  name and project, then its old times struck through and what they become.
  """
  def trim_action_card(assigns) do
    assigns = assign(assigns, :session, elem(assigns.action, 1))

    ~H"""
    <li class="flex flex-col gap-1 rounded-sm border border-grey-100 p-2">
      <.session_heading title={@session.title} project={@projects_by_id[@session.project_id]}>
        <%!-- Figma sets these badges' text a step lighter (700) than the badge primitive. --%>
        <.badge
          tone={trim_action_tone(@action)}
          class={[
            if(trim_action_tone(@action) == "danger", do: "text-brick-700!", else: "text-grey-700!")
          ]}
        >
          {trim_action_label(@action)}
        </.badge>
      </.session_heading>
      <p class="text-sm/[1.4] text-grey-500 tabular-nums">
        <span class="line-through">{time_range(@session.start_datetime, @session.end_datetime, @timezone)}</span>{trim_action_after(
          @action,
          @session,
          @timezone,
          @edited
        )}
      </p>
    </li>
    """
  end

  attr :title, :string, required: true
  attr :project, :any, default: nil
  slot :inner_block

  defp session_heading(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      {render_slot(@inner_block)}
      <p class="min-w-0 flex-1 truncate text-sm/[1.4] font-medium text-grey-900">{@title}</p>
      <p :if={@project} class="shrink-0 text-xs/[1.4] font-medium text-grey-500 uppercase">
        {@project.name}
      </p>
    </div>
    """
  end

  # What follows the struck-through times: an arrow and the new times, or why it goes away.
  defp trim_action_after({:trim_end, session, new_end}, _session, timezone, _edited),
    do: new_times(time_range(session.start_datetime, new_end, timezone))

  defp trim_action_after({:trim_start, session, new_start}, _session, timezone, _edited),
    do: new_times(time_range(new_start, session.end_datetime, timezone))

  defp trim_action_after({:split, session, new_end, remainder}, _session, timezone, _edited) do
    new_times(
      gettext("%{first} and %{second}",
        first: time_range(session.start_datetime, new_end, timezone),
        second: time_range(remainder.start_datetime, remainder.end_datetime, timezone)
      )
    )
  end

  defp trim_action_after({:delete, _session}, _session2, _timezone, edited) do
    assigns = %{
      reason:
        if(edited,
          do: gettext("fits entirely in this session"),
          else: gettext("fits entirely in the new session")
        )
    }

    ~H|<span class="mx-2">·</span>{@reason}|
  end

  defp new_times(range) do
    assigns = %{range: range}
    # Figma's two spaces either side of the arrow, about 8px at 14px.
    ~H|<span class="mx-2">→</span><span class="font-medium text-grey-900">{@range}</span>|
  end

  defp time_range(start, finish, timezone),
    do: "#{format_datetime_local(start, timezone)}–#{format_datetime_local(finish, timezone)}"

  # ── Helpers ──────────────────────────────────────────────────────────

  defp trim_action_label(action) do
    case action do
      {:trim_end, _, _} -> pgettext("session overlap action", "Shortened")
      {:trim_start, _, _} -> pgettext("session overlap action", "Shortened")
      {:delete, _} -> pgettext("session overlap action", "Deleted")
      {:split, _, _, _} -> pgettext("session overlap action", "Split")
    end
  end

  # Neutral for a session that only shrinks or splits, brick for one that goes away.
  defp trim_action_tone({:delete, _}), do: "danger"
  defp trim_action_tone(_action), do: "neutral"

  defp format_datetime_local(nil, _timezone), do: gettext("now (ongoing)")

  defp format_datetime_local(%DateTime{} = dt, timezone) do
    dt
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%H:%M")
  end

  defp format_date_local(%DateTime{} = dt, timezone) do
    dt
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
    |> Calendar.strftime("%d.%m")
  end
end
