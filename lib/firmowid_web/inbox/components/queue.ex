defmodule FirmowidWeb.Inbox.Components.Queue do
  @moduledoc """
  Inbox building blocks: queue rows grouped by tier, the member's session, who
  works today and the month in numbers.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Inbox.Utilities.Queue

  @doc """
  A queue item as a full-width row with a link to where it is dealt with. Only
  urgent items get the solid black button, so the rest does not compete with them.
  """
  attr :item, :map, required: true

  def item_row(assigns) do
    ~H"""
    <article
      id={"item-#{@item.id}"}
      class="flex items-center gap-4 border-b border-grey-200 px-5 py-4 last:border-b-0 max-md:flex-col max-md:items-start max-md:gap-3 max-md:px-4"
    >
      <div class="flex min-w-0 flex-1 items-start gap-4">
        <span class={[
          "flex size-9 shrink-0 items-center justify-center rounded-md",
          if(@item.tier == :urgent,
            do: "bg-brick-200 text-brick-800",
            else: "bg-grey-200 text-grey-800"
          )
        ]}>
          <Lucideicons.render! name={@item.icon} class="size-4" aria-hidden="true" />
        </span>
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <h3 class="text-sm font-medium text-grey-900">{@item.title}</h3>
          <p class="text-sm text-grey-600">
            <span :if={@item.person} class="font-medium text-grey-800">{@item.person} ·</span>
            {@item.context}
          </p>
        </div>
      </div>
      <.link
        kind="button"
        navigate={@item.href}
        size="small"
        variant={if @item.tier == :urgent, do: "special", else: "secondary"}
        class="shrink-0"
      >
        {@item.action}<Lucideicons.arrow_right class="size-4" aria-hidden="true" />
      </.link>
    </article>
    """
  end

  @doc "Header of a queue section: tier name, count and why it matters."
  attr :tier, :atom, required: true
  attr :count, :integer, required: true

  def tier_header(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2">
      <h2 class="text-caps-sm font-medium tracking-wide text-grey-900 uppercase">
        {Queue.tier_label(@tier)}
      </h2>
      <span class={[
        "rounded-full px-1.5 text-xs font-medium",
        if(@tier == :urgent, do: "bg-brick-200 text-brick-800", else: "bg-grey-200 text-grey-700")
      ]}>
        {@count}
      </span>
      <p class="truncate text-xs text-grey-500 max-md:hidden">{Queue.tier_hint(@tier)}</p>
    </div>
    """
  end

  @doc "Shown when the queue is empty."
  def all_done(assigns) do
    ~H"""
    <.empty_state title={gettext("All done")} class="bg-white">
      <:icon><Lucideicons.circle_check_big class="size-8" aria-hidden="true" /></:icon>
      {gettext("Nothing is waiting for your decision. New items will show up here on their own.")}
    </.empty_state>
    """
  end

  @doc """
  The member's session: the running one with a stop button, or the last one to
  continue with a start button. Without any session yet, the way to Czasośledź.
  """
  attr :session, :any, required: true, doc: "the running `Firmowid.Timetracker.Session` or nil"

  attr :last_session, :any,
    required: true,
    doc: "the most recent `Firmowid.Timetracker.Session` or nil"

  def session_panel(assigns) do
    ~H"""
    <section class="flex flex-col gap-3 rounded-md bg-white p-5">
      <div class="flex items-center justify-between">
        <h2 class="text-caps-sm font-medium tracking-wide text-grey-500 uppercase">
          {gettext("Your session")}
        </h2>
        <span
          :if={@session}
          class="inline-flex items-center gap-1.5 text-xs font-medium text-moss-700"
        >
          <span class="size-2 animate-pulse rounded-full bg-moss-600"></span>
          {pgettext("session state", "Running")}
        </span>
      </div>
      <%= if @session do %>
        <span
          id="inbox-session-timer"
          phx-hook="Timer"
          data-start_time={DateTime.to_iso8601(@session.start_datetime)}
          data-format="short"
          class="text-3xl font-semibold text-grey-900 tabular-nums"
        >
          00:00
        </span>
        <p class="truncate text-xs text-grey-500">{session_summary(@session)}</p>
      <% else %>
        <span class="text-3xl font-semibold text-grey-400 tabular-nums">00:00</span>
        <p :if={@last_session} class="truncate text-xs text-grey-500">
          {gettext("Continue: %{session}", session: session_summary(@last_session))}
        </p>
        <p :if={!@last_session} class="text-xs text-grey-500">
          {gettext("You are not tracking time now.")}
        </p>
      <% end %>
      <div class="flex items-center justify-between gap-3">
        <.button
          :if={@session}
          type="button"
          size="small"
          variant="secondary"
          phx-click="stop_session"
        >
          <Lucideicons.square class="size-4" aria-hidden="true" />{pgettext("session", "Stop")}
        </.button>
        <.button
          :if={!@session && @last_session}
          type="button"
          size="small"
          variant="special"
          phx-click="start_session"
        >
          <Lucideicons.play class="size-4" aria-hidden="true" />{pgettext("session", "Start")}
        </.button>
        <.link
          kind="button"
          navigate={~p"/czasosledz"}
          size="small"
          variant="ghost"
          class="ml-auto"
        >
          {pgettext("main navigation", "Time tracking")}
          <Lucideicons.arrow_right class="size-4" aria-hidden="true" />
        </.link>
      </div>
    </section>
    """
  end

  defp session_summary(session) do
    Enum.join(
      [
        session.title,
        session.project.name,
        if(session.is_remote,
          do: pgettext("presence", "remotely"),
          else: pgettext("presence", "in the office")
        )
      ],
      " · "
    )
  end

  @doc "Who works today and where."
  attr :presence, :list,
    required: true,
    doc: "from `Firmowid.Timetracker.Session.team_presence/2`"

  def office_panel(assigns) do
    ~H"""
    <section class="flex flex-col gap-3 rounded-md bg-white p-5">
      <div class="flex items-center justify-between gap-2">
        <h2 class="text-caps-sm font-medium tracking-wide text-grey-500 uppercase">
          {gettext("Today at the company")}
        </h2>
        <span class="text-xs text-grey-500">
          {gettext("%{working} of %{count} working",
            working: Enum.count(@presence, &(&1.status in [:office, :remote])),
            count: length(@presence)
          )}
        </span>
      </div>
      <ul class="flex flex-col gap-2">
        <li :for={person <- @presence} class="flex items-center gap-2 text-sm">
          <span class={[
            "size-2 shrink-0 rounded-full",
            person.status == :office && "bg-moss-600",
            person.status == :remote && "bg-moss-300",
            person.status in [:leave, :away] && "bg-grey-300"
          ]}></span>
          <span class="min-w-0 flex-1 truncate text-grey-800">
            {person.name || pgettext("presence", "Unnamed member")}
          </span>
          <span class="shrink-0 text-xs text-grey-500">{status_label(person.status)}</span>
        </li>
      </ul>
    </section>
    """
  end

  defp status_label(:office), do: pgettext("presence", "in the office")
  defp status_label(:remote), do: pgettext("presence", "remotely")
  defp status_label(:leave), do: pgettext("presence", "absent")
  defp status_label(:away), do: pgettext("presence", "not working")

  @doc "The month in numbers as quiet label and value rows, for a side column."
  attr :month, :list, required: true

  def month_list(assigns) do
    ~H"""
    <section class="flex flex-col gap-3 rounded-md bg-white p-5">
      <h2 class="text-caps-sm font-medium tracking-wide text-grey-500 uppercase">
        {gettext("This month")}
      </h2>
      <dl class="flex flex-col gap-2.5">
        <div :for={kpi <- @month} class="flex items-baseline justify-between gap-3">
          <dt class="truncate text-sm text-grey-700">{kpi.label}</dt>
          <dd class={[
            "shrink-0 text-sm font-semibold tabular-nums",
            if(kpi.side == :sales, do: "text-teal-700", else: "text-rust-700")
          ]}>
            {kpi.value}
          </dd>
        </div>
      </dl>
    </section>
    """
  end
end
