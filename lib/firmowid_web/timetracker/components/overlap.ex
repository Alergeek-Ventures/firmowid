defmodule FirmowidWeb.Timetracker.Components.Overlap do
  @moduledoc """
  Display components for the overlap confirmation modal in the timetracker.

  Renders the "new session" preview card, affected session cards with
  before/after comparisons, and action badges (trim, delete, split).
  """
  use FirmowidWeb, :html

  # ── New session preview ──────────────────────────────────────────────

  attr :title, :string, required: true
  attr :start_datetime, :any, required: true
  attr :end_datetime, :any, required: true
  attr :date, :any, required: true
  attr :timezone, :string, required: true

  @doc "Green card previewing the new session that will be created."
  def new_session_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-moss-200 bg-moss-100 p-4">
      <div class="mb-1 flex items-center gap-2">
        <span class="inline-flex items-center rounded-full bg-moss-200 px-2 py-0.5 text-xs font-medium text-moss-700">
          {gettext("New session")}
        </span>
        <span class="text-sm font-medium text-grey-900">
          {@title}
        </span>
      </div>
      <p class="text-sm text-moss-700">
        {format_date_local(@date, @timezone)}, {format_datetime_local(@start_datetime, @timezone)} – {format_datetime_local(
          @end_datetime,
          @timezone
        )}
      </p>
    </div>
    """
  end

  # ── Affected session card ────────────────────────────────────────────

  attr :action, :any, required: true
  attr :timezone, :string, required: true
  attr :projects_by_id, :map, required: true

  @doc "Card showing an existing session's before/after state for a trim action."
  def trim_action_card(assigns) do
    assigns = assign(assigns, :session, elem(assigns.action, 1))

    ~H"""
    <div class="rounded-lg border border-grey-200 bg-grey-50 p-4">
      <div class="mb-2 flex items-center justify-between gap-2">
        <div class="flex min-w-0 items-center gap-2">
          <span class={[
            "inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-xs font-medium",
            trim_action_badge_styles(@action)
          ]}>
            {trim_action_label(@action)}
          </span>
          <span class="truncate text-sm font-medium text-grey-900">
            {@session.title}
          </span>
        </div>
        <span
          :if={@projects_by_id[@session.project_id]}
          class="shrink-0 text-xs text-grey-700"
        >
          {Map.get(@projects_by_id, @session.project_id).name}
        </span>
      </div>

      <div class="flex flex-col gap-1 text-sm">
        <div class="flex items-center gap-2">
          <span class="w-12 shrink-0 text-grey-700">{gettext("Before:")}</span>
          <span class="text-grey-700 line-through">
            {format_datetime_local(@session.start_datetime, @timezone)} – {format_datetime_local(
              @session.end_datetime,
              @timezone
            )}
          </span>
        </div>

        <.trim_action_after action={@action} session={@session} timezone={@timezone} />
      </div>
    </div>
    """
  end

  # ── Trim action after ───────────────────────────────────────────────

  attr :action, :any, required: true
  attr :session, :any, required: true
  attr :timezone, :string, required: true

  defp trim_action_after(%{action: {:trim_end, _, new_end}} = assigns) do
    assigns = assign(assigns, :new_end, new_end)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="w-12 shrink-0 text-grey-700">{gettext("After:")}</span>
      <span class="font-medium text-grey-900">
        {format_datetime_local(@session.start_datetime, @timezone)} – {format_datetime_local(
          @new_end,
          @timezone
        )}
      </span>
    </div>
    """
  end

  defp trim_action_after(%{action: {:trim_start, _, new_start}} = assigns) do
    assigns = assign(assigns, :new_start, new_start)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="w-12 shrink-0 text-grey-700">{gettext("After:")}</span>
      <span class="font-medium text-grey-900">
        {format_datetime_local(@new_start, @timezone)} – {format_datetime_local(
          @session.end_datetime,
          @timezone
        )}
      </span>
    </div>
    """
  end

  defp trim_action_after(%{action: {:delete, _}} = assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="w-12 shrink-0 text-grey-700">{gettext("After:")}</span>
      <span class="font-medium text-brick-700">{gettext("The session will be deleted")}</span>
    </div>
    """
  end

  defp trim_action_after(%{action: {:split, _, new_end, remainder}} = assigns) do
    assigns = assign(assigns, new_end: new_end, remainder: remainder)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="w-12 shrink-0 text-grey-700">{gettext("After:")}</span>
      <div class="flex flex-col gap-0.5">
        <span class="font-medium text-grey-900">
          {format_datetime_local(@session.start_datetime, @timezone)} – {format_datetime_local(
            @new_end,
            @timezone
          )}
        </span>
        <span class="font-medium text-grey-900">
          {format_datetime_local(@remainder.start_datetime, @timezone)} – {format_datetime_local(
            @remainder.end_datetime,
            @timezone
          )}
        </span>
      </div>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp trim_action_label(action) do
    case action do
      {:trim_end, _, _} -> pgettext("session overlap action", "Shortened")
      {:trim_start, _, _} -> pgettext("session overlap action", "Shortened")
      {:delete, _} -> pgettext("session overlap action", "Deleted")
      {:split, _, _, _} -> pgettext("session overlap action", "Split")
    end
  end

  defp trim_action_badge_styles(action) do
    case action do
      {:trim_end, _, _} -> "bg-rust-200 text-rust-700"
      {:trim_start, _, _} -> "bg-rust-200 text-rust-700"
      {:delete, _} -> "bg-brick-200 text-brick-700"
      {:split, _, _, _} -> "bg-teal-200 text-teal-800"
    end
  end

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
