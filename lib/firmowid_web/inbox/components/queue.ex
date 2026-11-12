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
  A queue item: a tile coloured by its kind, the title, one meta line and its
  actions. Urgent items get the solid black button, leave requests decide in
  place and everything else opens its page.
  """
  attr :item, :map, required: true
  attr :fresh, :boolean, default: false, doc: "arrived while the page was open; it lights up once"

  def item_row(assigns) do
    assigns = assign(assigns, :decisions, Map.get(assigns.item, :decisions, []))

    ~H"""
    <article
      id={"item-#{@item.id}"}
      class={[
        "flex items-center gap-4 border-b border-grey-100 px-5 py-4 last:border-b-0 max-md:flex-wrap max-md:gap-y-3 max-md:px-4",
        @fresh && "motion-safe:animate-arrive"
      ]}
    >
      <%!-- Level with the text's top, as next to a two-line text, however long it runs. --%>
      <span class={[
        "mt-0.5 flex size-10 shrink-0 items-center justify-center self-start rounded-sm",
        icon_styles(@item)
      ]}>
        <Lucideicons.render! name={@item.icon} class="size-6" aria-hidden="true" />
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <h3 class="text-base leading-[normal] font-medium text-black">
          {@item.title}<span :if={Map.has_key?(@item, :date_range)}>,
          <span class="whitespace-nowrap">{@item.date_range}</span></span>
        </h3>
        <p class="flex min-w-0 flex-wrap gap-x-1.5 text-sm leading-[1.35] text-grey-600">
          <span
            :if={@item.person}
            class="min-w-0 truncate text-black"
            title={@item.person}
          >
            {@item.person}
          </span>
          <span :if={@item.person} aria-hidden="true">·</span>
          <span>
            {@item.context}
            <span :if={Map.get(@item, :days_late, 0) > 0} class="text-brick-700">
              {ngettext("(%{count} day late)", "(%{count} days late)", @item.days_late)}
            </span>
          </span>
        </p>
      </div>
      <%!-- On phones the actions wrap under the text, level with the title. --%>
      <div class="flex shrink-0 flex-wrap items-center gap-4 max-md:w-full max-md:justify-end max-md:pl-14">
        <%= if @item.tier == :urgent do %>
          <.link kind="button" navigate={@item.href} size="small" variant="special">
            {@item.action}
          </.link>
        <% else %>
          <div :if={@decisions != []} class="flex items-center gap-2">
            <%!-- Holds the ✕'s place when an item cannot be rejected, so the buttons line up across rows. --%>
            <span :if={length(@decisions) == 1} class="w-8 shrink-0" aria-hidden="true"></span>
            <%= for decision <- Enum.sort_by(@decisions, & &1.show_label?) do %>
              <.icon_button
                :if={!decision.show_label?}
                id={"item-#{@item.id}-#{decision.action}"}
                label={decision.label}
                variant="secondary"
                class="w-8"
                phx-click="decide_item"
                phx-value-id={@item.id}
                phx-value-decision={decision.action}
                phx-disable-with=""
              >
                <Lucideicons.render! name={decision.icon} aria-hidden="true" />
              </.icon_button>
              <.button
                :if={decision.show_label?}
                id={"item-#{@item.id}-#{decision.action}"}
                type="button"
                size="small"
                variant="secondary"
                phx-click="decide_item"
                phx-value-id={@item.id}
                phx-value-decision={decision.action}
                phx-disable-with=""
              >
                <Lucideicons.render! name={decision.icon} aria-hidden="true" />{decision.label}
              </.button>
            <% end %>
          </div>
          <.link
            kind="button"
            navigate={@item.href}
            size="small"
            variant={if @decisions == [], do: "secondary", else: "outline"}
          >
            {@item.action}
          </.link>
        <% end %>
      </div>
    </article>
    """
  end

  defp icon_styles(%{tier: :urgent}), do: "bg-brick-200 text-brick-700"
  defp icon_styles(%{tier: :books, side: :cost}), do: "bg-rust-200 text-rust-700"
  defp icon_styles(%{tier: :books, side: :sales}), do: "bg-teal-200 text-teal-700"
  defp icon_styles(_item), do: "bg-grey-100 text-grey-900"

  @doc "Header of a queue group: its name, how many items it has and why it matters."
  attr :tier, :atom, required: true
  attr :count, :integer, required: true

  def tier_header(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <h2 class={[
        "text-caps-sm font-medium uppercase",
        if(@tier == :urgent, do: "text-brick-700", else: "text-grey-900")
      ]}>
        {Queue.tier_label(@tier)}
      </h2>
      <span class={[
        "flex size-4.5 shrink-0 items-center justify-center rounded-full text-caps-sm font-semibold tabular-nums",
        if(@tier == :urgent, do: "bg-brick-200 text-brick-700", else: "bg-grey-200 text-grey-700")
      ]}>
        {@count}
      </span>
      <p class="truncate text-sm text-grey-600 max-md:hidden">{Queue.tier_hint(@tier)}</p>
    </div>
    """
  end

  @doc "Shown in place of the queue when nothing waits."
  attr :class, :any, default: nil

  def all_done(assigns) do
    ~H"""
    <.empty_state size="small" title={gettext("Nothing is waiting for your decision.")} class={@class}>
      <:icon><Lucideicons.circle_check_big class="text-moss-700" aria-hidden="true" /></:icon>
      {gettext("New items will show up here on their own.")}
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

  @doc """
  Who works today: a dot for the office, a ring for remote work, a grey dot
  for the others. The list stops where the queue or the first screen ends,
  whichever is lower; the rest folds into one row that unfolds in place. Until
  the page measures itself, only the people who do not work are folded.
  """
  attr :presence, :list,
    required: true,
    doc: "from `Firmowid.Timetracker.Session.team_presence/2`"

  attr :fit_to, :string,
    default: nil,
    doc: "id of the queue the list may grow along; nil fits the first screen only"

  def office_panel(assigns) do
    {working, absent} = Enum.split_with(assigns.presence, &(&1.status in [:office, :remote]))
    total = length(assigns.presence)

    assigns =
      assign(assigns,
        working: working,
        people: working ++ absent,
        absent_count: length(absent),
        absent_labels:
          Map.new(1..max(length(absent), 1)//1, fn n ->
            {n, ngettext("%{count} person is not working", "%{count} people are not working", n)}
          end),
        more_labels: Map.new(1..max(total, 1)//1, &{&1, gettext("Show %{count} more", count: &1)})
      )

    ~H"""
    <section
      id="inbox-presence"
      phx-hook=".PresenceFit"
      data-fit-to={@fit_to}
      data-absent-labels={JSON.encode!(@absent_labels)}
      data-more-labels={JSON.encode!(@more_labels)}
      data-collapse-label={gettext("Collapse")}
      class="flex flex-col gap-4 rounded-sm bg-white px-5 pt-5 pb-4"
    >
      <div class="flex items-center justify-between gap-2 text-grey-600">
        <h2 class="text-caps-sm font-medium uppercase">{gettext("Today at the company")}</h2>
        <span class="text-sm tabular-nums">
          <span aria-hidden="true">{length(@working)}/{length(@presence)}</span>
          <span class="sr-only">
            {gettext("%{working} of %{count} working",
              working: length(@working),
              count: length(@presence)
            )}
          </span>
        </span>
      </div>
      <div class="flex flex-col gap-3">
        <ul id="inbox-presence-people" class="flex flex-col gap-3">
          <li
            :for={person <- @people}
            data-person
            data-absent={person.status not in [:office, :remote]}
            hidden={person.status not in [:office, :remote]}
            class="flex items-center gap-2.5 text-sm"
          >
            <.presence_dot status={person.status} />
            <span class="min-w-0 flex-1 truncate text-black">{person_name(person)}</span>
            <span class="sr-only">{status_label(person.status)}</span>
          </li>
        </ul>
        <.button
          :if={@people != []}
          type="button"
          variant="unstyled"
          id="inbox-presence-fold"
          data-fold
          hidden={@absent_count == 0}
          aria-expanded="false"
          aria-controls="inbox-presence-people"
          class="group flex w-full cursor-pointer items-center gap-2.5 text-left text-sm text-grey-600 hover:text-grey-900"
        >
          <span data-fold-dot class="flex"><.presence_dot status={:away} /></span>
          <span data-fold-label class="min-w-0 flex-1">{Map.get(@absent_labels, @absent_count)}</span>
          <Lucideicons.chevron_down
            class="size-4 shrink-0 transition-transform group-aria-expanded:rotate-180"
            aria-hidden="true"
          />
        </.button>
      </div>
      <div class="h-px bg-grey-100"></div>
      <ul class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-grey-600" aria-hidden="true">
        <li :for={status <- [:office, :remote, :away]} class="flex items-center gap-1.5">
          <.presence_dot status={status} />{status_label(status)}
        </li>
      </ul>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PresenceFit">
        // Keeps the panel within the first screen, or along the queue when that
        // is longer, folding the people that do not fit. Stacked under the queue
        // on narrow screens, it folds only the people who do not work.
        const BOTTOM_GAP = 32

        export default {
          mounted() {
            this.expanded = false
            this.onClick = (e) => {
              if (!e.target.closest("[data-fold]")) return
              const rows = [...this.el.querySelectorAll("[data-person]")]
              const shown = new Set(rows.filter((row) => !row.hidden))
              const list = this.el.querySelector("#inbox-presence-people")
              const from = list.getBoundingClientRect().height
              this.expanded = !this.expanded
              this.fit()
              this.animate(list, from, rows.filter((row) => !row.hidden && !shown.has(row)))
            }
            this.onResize = () => this.fit()
            this.el.addEventListener("click", this.onClick)
            window.addEventListener("resize", this.onResize)
            const queue = this.queue()
            if (queue && window.ResizeObserver) {
              this.observer = new ResizeObserver(() => this.fit())
              this.observer.observe(queue)
            }
            this.fit()
          },
          updated() { this.fit() },
          destroyed() {
            window.removeEventListener("resize", this.onResize)
            this.observer?.disconnect()
          },
          queue() {
            return this.el.dataset.fitTo && document.getElementById(this.el.dataset.fitTo)
          },
          fit() {
            const rows = [...this.el.querySelectorAll("[data-person]")]
            const fold = this.el.querySelector("[data-fold]")
            if (!fold) return
            const working = rows.filter((row) => !row.hasAttribute("data-absent")).length
            // Works out the fold as if folded, then unfolds everyone again when expanded.
            const expanded = this.expanded
            this.expanded = false
            const stacked = this.el.closest("aside").getBoundingClientRect().top >
              this.el.closest("aside").previousElementSibling.getBoundingClientRect().bottom
            this.show(rows, fold, rows.length)
            if (stacked) {
              this.show(rows, fold, working)
            } else {
              const queue = this.queue()
              const queueBottom = queue ? queue.getBoundingClientRect().bottom + window.scrollY : 0
              const limit = Math.max(window.innerHeight, queueBottom) - BOTTOM_GAP
              let visible = rows.length
              while (visible > 0 && this.el.getBoundingClientRect().bottom + window.scrollY > limit) {
                this.show(rows, fold, --visible)
              }
            }
            // With nobody left to fold there is nothing to collapse either.
            this.expanded = expanded && !fold.hidden
            if (this.expanded) {
              rows.forEach((row) => { row.hidden = false })
              fold.setAttribute("aria-expanded", "true")
              fold.querySelector("[data-fold-label]").textContent = this.el.dataset.collapseLabel
              fold.querySelector("[data-fold-dot]").hidden = true
            }
          },
          // Slides the list from its old height and fades the unfolded people in.
          animate(list, from, unfolded) {
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
            const to = list.getBoundingClientRect().height
            if (Math.abs(to - from) < 1) return
            const timing = { duration: 250, easing: "cubic-bezier(0.23, 1, 0.32, 1)" }
            list.animate([{ height: `${from}px`, overflow: "hidden" }, { height: `${to}px`, overflow: "hidden" }], timing)
            unfolded.forEach((row) => row.animate([{ opacity: 0 }, { opacity: 1 }], timing))
          },
          // Shows the first `visible` people and names the folded ones on the toggle.
          show(rows, fold, visible) {
            const folded = rows.slice(visible)
            rows.forEach((row, i) => { row.hidden = i >= visible })
            fold.hidden = folded.length === 0
            fold.setAttribute("aria-expanded", "false")
            if (!folded.length) return
            const onlyAbsent = folded.every((row) => row.hasAttribute("data-absent"))
            const labels = JSON.parse(this.el.dataset[onlyAbsent ? "absentLabels" : "moreLabels"])
            fold.querySelector("[data-fold-label]").textContent = labels[folded.length]
            fold.querySelector("[data-fold-dot]").hidden = !onlyAbsent
          }
        }
      </script>
    </section>
    """
  end

  attr :status, :atom, required: true

  defp presence_dot(assigns) do
    ~H"""
    <span class={["size-2 shrink-0 rounded-full", presence_dot_styles(@status)]}></span>
    """
  end

  defp presence_dot_styles(:office), do: "bg-moss-700"
  defp presence_dot_styles(:remote), do: "border-[1.5px] border-moss-700"
  defp presence_dot_styles(_absent), do: "bg-grey-300"

  defp person_name(person), do: person.name || pgettext("presence", "Unnamed member")

  defp status_label(:office), do: pgettext("presence", "in the office")
  defp status_label(:remote), do: pgettext("presence", "remotely")
  defp status_label(_absent), do: pgettext("presence", "not working")

  @doc "The member's recorded time this month, using the same quiet rows as the company summary."
  attr :duration, :integer, required: true, doc: "session seconds from Session.month_duration/2"

  def personal_month(assigns) do
    ~H"""
    <section id="inbox-personal-month" class="flex flex-col gap-3 rounded-md bg-white p-5">
      <h2 class="text-caps-sm font-medium tracking-wide text-grey-500 uppercase">
        {gettext("This month")}
      </h2>
      <dl class="flex flex-col gap-2.5">
        <div class="flex items-baseline justify-between gap-3">
          <dt class="truncate text-sm text-grey-700">{gettext("Hours worked")}</dt>
          <dd class="shrink-0 text-sm font-semibold text-grey-800 tabular-nums">
            {hours_and_minutes(@duration)}
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  # Whole hours read better without "0 min".
  defp hours_and_minutes(seconds) do
    case {div(seconds, 3600), rem(div(seconds, 60), 60)} do
      {hours, 0} -> pgettext("duration", "%{hours} h", hours: hours)
      {hours, minutes} -> gettext("%{hours} h %{minutes} min", hours: hours, minutes: minutes)
    end
  end

  @doc "The month in numbers as quiet label and value rows, for a side column."
  attr :month, :list, required: true

  def month_list(assigns) do
    ~H"""
    <section class="flex flex-col gap-2.5 rounded-sm bg-white p-5">
      <h2 class="text-caps-sm font-medium text-grey-600 uppercase">{gettext("This month")}</h2>
      <dl class="flex flex-col gap-2.5">
        <div :for={kpi <- @month} class="flex items-baseline justify-between gap-3 text-sm">
          <dt class="truncate text-grey-700">{kpi.label}</dt>
          <dd class={[
            "shrink-0 font-medium tabular-nums",
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
