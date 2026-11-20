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
  alias FirmowidWeb.Invoicing.Components.CostInvoiceUpload

  @doc """
  A queue item: a tile coloured by its kind, the title, one meta line and its
  actions. Urgent items get the solid black button, leave requests decide in
  place and everything else opens its page.
  """
  attr :item, :map, required: true
  attr :fresh, :boolean, default: false, doc: "arrived while the page was open; it lights up once"

  attr :today, Date,
    required: true,
    doc: "the organization's today, for the days the menu puts it aside until"

  def item_row(assigns) do
    assigns = assign(assigns, :decisions, Map.get(assigns.item, :decisions, []))

    ~H"""
    <article
      id={"item-#{@item.id}"}
      class={[
        "group/row flex items-center gap-4 border-b border-grey-100 px-5 py-4 last:border-b-0 max-md:flex-wrap max-md:gap-y-3 max-md:px-4",
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
        <h3 class="text-base/[normal] font-medium text-black">
          {@item.title}<span :if={Map.has_key?(@item, :date_range)}>,
          <span class="whitespace-nowrap">{@item.date_range}</span></span>
        </h3>
        <p class="flex min-w-0 flex-wrap gap-x-1.5 text-sm/[1.35] text-grey-600">
          <span
            :if={@item.person}
            class="min-w-0 truncate text-black"
            title={@item.person}
          >
            {@item.person}
          </span>
          <span :if={@item.person} aria-hidden="true">·</span>
          <span>{@item.context}</span>
        </p>
      </div>
      <div
        :if={Map.has_key?(@item, :amount)}
        class="flex shrink-0 flex-col items-end gap-1 whitespace-nowrap"
      >
        <p class="text-base/[normal] font-medium text-black">{@item.amount}</p>
        <p class="text-sm/[1.35] text-brick-700">
          {ngettext("%{count} day late", "%{count} days late", @item.days_late)}
        </p>
      </div>
      <%!-- On phones the actions wrap under the text, level with the title. --%>
      <div class="flex shrink-0 flex-wrap items-center gap-2 max-md:w-full max-md:justify-end max-md:pl-14">
        <%= if @item.tier == :urgent do %>
          <.link kind="button" navigate={@item.href} size="small" variant="special">
            {@item.action}
          </.link>
        <% else %>
          <div :if={@decisions != []} class="flex items-center gap-2">
            <%!-- Holds the ✕'s place when an item cannot be rejected, so the buttons line up across rows;
            on phones the actions sit right-aligned on their own line, where it would only crowd them. --%>
            <span :if={length(@decisions) == 1} class="w-8 shrink-0 max-md:hidden" aria-hidden="true"></span>
            <%= for decision <- Enum.sort_by(@decisions, & &1.show_label?) do %>
              <.icon_button
                :if={!decision.show_label?}
                id={"item-#{@item.id}-#{decision.action}"}
                label={decision.label}
                variant="tertiary"
                class="w-8"
                phx-click={leave(@item.id, "decide_item", %{decision: decision.action})}
              >
                <Lucideicons.render! name={decision.icon} aria-hidden="true" />
              </.icon_button>
              <.button
                :if={decision.show_label?}
                id={"item-#{@item.id}-#{decision.action}"}
                type="button"
                size="small"
                variant="tertiary"
                phx-click={leave(@item.id, "decide_item", %{decision: decision.action})}
              >
                <Lucideicons.render! name={decision.icon} aria-hidden="true" />{decision.label}
              </.button>
            <% end %>
          </div>
          <.link
            kind="button"
            navigate={@item.href}
            size="small"
            variant={if @decisions == [], do: "tertiary", else: "outline"}
          >
            {@item.action}
          </.link>
        <% end %>
        <.snooze_menu item={@item} today={@today} />
      </div>
    </article>
    """
  end

  # Hands `event` for the item to the card's SmoothHeight hook
  # (`inbox:leave`): the row dissolves first, then the hook sends the event and
  # the rows under it glide up once the answer takes it off.
  defp leave(id, event, value \\ %{}) do
    JS.dispatch("inbox:leave",
      to: "#item-#{id}",
      detail: %{event: event, value: Map.put(value, :id, id)}
    )
  end

  attr :item, :map, required: true
  attr :today, Date, required: true

  # Puts the item aside for the whole company (`Firmowid.Core.InboxSnooze`);
  # each option shows the day the item comes back.
  defp snooze_menu(assigns) do
    ~H"""
    <.menu
      id={"item-#{@item.id}-snooze"}
      label={gettext("Put aside")}
      trigger_class="group-hover/row:text-grey-900"
      panel_class="w-70"
    >
      <p class="px-3 py-2 text-caps-sm/none font-medium text-grey-600 uppercase" aria-hidden="true">
        {gettext("Put aside until")}
      </p>
      <.menu_item
        :for={{days, label} <- snooze_options()}
        class="justify-between gap-4"
        phx-click={leave(@item.id, "snooze_item", %{days: to_string(days)})}
      >
        <span class="font-medium text-black">{label}</span>
        <span class="text-grey-600">{comes_back(Date.add(@today, days), @today)}</span>
      </.menu_item>
      <div class="my-1 h-px bg-grey-100" role="separator"></div>
      <.menu_item
        tone="danger"
        class="flex-col items-start gap-1 py-2"
        phx-click={leave(@item.id, "snooze_item")}
      >
        <span class="font-medium">{gettext("Hide this item")}</span>
        <span class="text-sm/[1.35] whitespace-normal text-grey-600">{hide_for_good_note(@item)}</span>
      </.menu_item>
    </.menu>
    """
  end

  defp snooze_options, do: [{7, gettext("In a week")}, {30, gettext("In a month")}, {90, gettext("In 3 months")}]

  # "śr 18.11", with the year once it is another one: "wt 9.02.2027". The
  # abbreviated weekday loses its dot ("śr." in CLDR).
  defp comes_back(date, today) do
    format = if date.year == today.year, do: "d.MM", else: "d.MM.y"
    weekday = date |> Firmowid.Cldr.Date.to_string!(format: "EEE") |> String.trim_trailing(".")

    "#{weekday} #{Firmowid.Cldr.Date.to_string!(date, format: format)}"
  end

  defp hide_for_good_note(%{days_late: _}),
    do: gettext("It will not come back to the inbox, even if the invoice is still overdue.")

  defp hide_for_good_note(_item), do: gettext("It will not come back to the inbox until someone brings it back.")

  @doc """
  Items the company put aside, folded under the queue: each says when it comes
  back and can be brought back right away.
  """
  attr :entries, :list,
    required: true,
    doc: "`{item, snooze}` pairs from `Queue.split_put_aside/2`"

  attr :expanded, :boolean, required: true

  def put_aside(assigns) do
    ~H"""
    <section id="inbox-put-aside" class="flex flex-col gap-3">
      <.button
        type="button"
        variant="unstyled"
        id="inbox-put-aside-toggle"
        aria-expanded={to_string(@expanded)}
        aria-controls="inbox-put-aside-list"
        phx-click="toggle_group"
        phx-value-tier="put_aside"
        class="flex cursor-pointer items-center gap-2 self-start text-grey-900 hover:text-black"
      >
        <h2 class="text-caps-sm font-medium uppercase">{pgettext("inbox section", "Put aside")}</h2>
        <span class="flex size-4.5 shrink-0 items-center justify-center rounded-full bg-grey-200 text-caps-sm font-semibold text-grey-700 tabular-nums">
          {length(@entries)}
        </span>
        <Lucideicons.chevron_up :if={@expanded} class="size-4" aria-hidden="true" />
        <Lucideicons.chevron_down :if={!@expanded} class="size-4" aria-hidden="true" />
        <span class="truncate text-sm/[1.35] text-grey-600 max-md:hidden">
          {gettext("Hidden for everyone in the company.")}
        </span>
      </.button>
      <div :if={@expanded} id="inbox-put-aside-list" class="overflow-hidden rounded-sm bg-white">
        <div
          :for={{item, snooze} <- @entries}
          id={"put-aside-#{item.id}"}
          class="flex items-center gap-4 border-b border-grey-100 px-5 py-3 last:border-b-0 max-md:px-4"
        >
          <div class="flex min-w-0 flex-1 flex-col gap-0.5">
            <%!-- Like the queue row, the date range and the person tell apart items of one kind. --%>
            <p class="truncate text-sm font-medium text-black">
              {item.title}<span :if={Map.has_key?(item, :date_range)}>, {item.date_range}</span>
            </p>
            <p class="flex min-w-0 flex-wrap gap-x-1.5 text-sm text-grey-600">
              <span :if={item.person} class="min-w-0 truncate text-black">{item.person}</span>
              <span :if={item.person} aria-hidden="true">·</span>
              <span>{put_aside_until(snooze)}</span>
            </p>
          </div>
          <.button
            type="button"
            size="small"
            variant="ghost"
            phx-click="restore_item"
            phx-value-id={item.id}
          >
            {gettext("Bring back")}
          </.button>
        </div>
      </div>
    </section>
    """
  end

  defp put_aside_until(%{until: nil}), do: gettext("Hidden for good")

  defp put_aside_until(%{until: until}),
    do:
      gettext("Comes back on %{date}",
        date: until |> DateTime.shift_zone!("Europe/Warsaw") |> Calendar.strftime("%d.%m.%Y")
      )

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
      <p class="truncate text-sm/[1.35] text-grey-600 max-md:hidden">
        {Queue.tier_hint(@tier)}
      </p>
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
  The actions the organization does most often, as small outlined buttons
  with an icon and the action's name. A button opens its page; the upload
  button opens the file picker and sends the chosen files at once.
  """
  attr :shortcuts, :list, required: true, doc: "from `FirmowidWeb.Inbox.Utilities.Shortcuts`"

  attr :upload, :any,
    required: true,
    doc: "the cost invoice upload, or nil for a member who may not add them"

  attr :uploading, :integer, default: 0, doc: "files of the upload still being sent"
  attr :processing, :integer, default: 0, doc: "cost invoice files still being read"

  def shortcuts(assigns) do
    ~H"""
    <section id="inbox-shortcuts" class="flex flex-col gap-3 pt-4">
      <div class="flex items-baseline gap-3">
        <h2 class="text-caps-sm/none font-medium text-grey-900 uppercase">
          {gettext("Shortcuts")}
        </h2>
        <p class="truncate text-sm/[1.35] text-grey-600 max-md:hidden">
          {gettext("What your company does most often.")}
        </p>
      </div>
      <ul class="flex flex-wrap gap-2">
        <li :for={shortcut <- @shortcuts}>
          <form
            :if={shortcut.target == :upload}
            id="inbox-upload-form"
            phx-change="upload"
            phx-submit="upload"
          >
            <.button
              as="label"
              id={"inbox-shortcut-#{shortcut.id}"}
              size="small"
              variant="outline"
              class="relative has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-(--focus-ring)"
            >
              <.live_file_input upload={@upload} class="sr-only" />
              <Lucideicons.render! name={shortcut.icon} aria-hidden="true" />{shortcut.label}
              <CostInvoiceUpload.processing_badge
                id="inbox-upload-count-indicator"
                uploading={@uploading}
                processing={@processing}
              />
            </.button>
          </form>
          <.link
            :if={shortcut.target != :upload}
            kind="button"
            id={"inbox-shortcut-#{shortcut.id}"}
            navigate={elem(shortcut.target, 1)}
            size="small"
            variant="outline"
          >
            <Lucideicons.render! name={shortcut.icon} aria-hidden="true" />{shortcut.label}
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  The member's session: the running one with a stop button and where it is
  worked from, or the last one to continue with a start button. Without any
  session yet, the way to Czasośledź. The time counts seconds live, in a
  lighter shade.

  The page renders it twice: large under the queue and compact for the side
  column. The `.SessionPlacement` hook of the inbox shows the compact one when
  the large one would not fit on the first screen.
  """
  attr :session, :any, required: true, doc: "the running `Firmowid.Timetracker.Session` or nil"

  attr :last_session, :any,
    required: true,
    doc: "the most recent `Firmowid.Timetracker.Session` or nil"

  attr :compact, :boolean, default: false

  def session_panel(assigns) do
    assigns =
      assign(
        assigns,
        :id,
        if(assigns.compact, do: "inbox-session-compact", else: "inbox-session")
      )

    ~H"""
    <section
      id={@id}
      class={[
        "relative flex-col overflow-hidden rounded-sm bg-white",
        if(@compact,
          do: "hidden gap-8 p-5 group-data-compact-session:flex",
          else: "flex min-h-65 justify-between gap-5 p-6 group-data-compact-session:hidden max-md:p-4"
        )
      ]}
    >
      <img
        :if={!@compact}
        src={~p"/images/figurine.png"}
        alt=""
        aria-hidden="true"
        class="pointer-events-none absolute -top-18 right-16.75 w-84.5 max-w-none opacity-5 select-none max-md:-right-24"
      />
      <div class="relative flex items-center justify-between gap-3">
        <h2 class="text-caps-sm font-medium text-grey-600 uppercase">{gettext("Your session")}</h2>
        <%!-- The compact card has no room for the badge; the switch takes its place. --%>
        <.workplace_switch :if={@compact && @session} id={@id} remote={@session.is_remote} />
        <span
          :if={!@compact && @session}
          class="inline-flex items-center gap-1.5 rounded-sm bg-moss-100 px-2 py-0.75 text-sm/[1.35] text-moss-800"
        >
          <span class="size-2 rounded-full bg-moss-700" aria-hidden="true"></span>
          {pgettext("session state", "Running")}
        </span>
      </div>
      <div class="relative flex flex-col gap-1">
        <span
          id={if @session, do: "#{@id}-timer", else: "#{@id}-idle"}
          phx-hook={@session && "Timer"}
          data-start_time={@session && DateTime.to_iso8601(@session.start_datetime)}
          class={[
            "leading-[normal] font-semibold tracking-[-0.02em] tabular-nums",
            if(@compact, do: "text-[2.5rem]", else: "text-[4rem]"),
            if(@session, do: "text-black", else: "text-grey-400")
          ]}
        >
          <span data-timer-main>00:00</span><span data-timer-seconds class="text-grey-200">:00</span>
        </span>
        <p class="truncate text-sm/[1.35] text-grey-600">
          <%= cond do %>
            <% @session -> %>
              {session_summary(@session)}
            <% @last_session -> %>
              {gettext("Continue: %{session}",
                session: session_summary(@last_session, with_workplace: true)
              )}
            <% true -> %>
              {gettext("You are not tracking time now.")}
          <% end %>
        </p>
      </div>
      <div class="relative flex flex-wrap items-center justify-between gap-3">
        <div class={["flex items-center gap-2", @compact && "w-full"]}>
          <.button
            :if={@session}
            type="button"
            size="small"
            variant="special"
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
            variant="outline"
            class={[@compact && "flex-1"]}
          >
            {gettext("Open Time tracking")}
          </.link>
        </div>
        <.workplace_switch :if={!@compact && @session} id={@id} remote={@session.is_remote} />
      </div>
    </section>
    """
  end

  attr :id, :string, required: true, doc: "id of the session card the switch belongs to"
  attr :remote, :boolean, required: true

  # Where the running session is worked from; switching it saves at once.
  defp workplace_switch(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={gettext("Workplace")}
      class="flex items-center gap-0.5 rounded-sm bg-grey-100 p-0.5"
    >
      <.button
        :for={
          {remote, label} <- [
            {false, pgettext("workplace", "In the office")},
            {true, pgettext("workplace", "Remotely")}
          ]
        }
        id={"#{@id}-#{if remote, do: "remote", else: "office"}"}
        type="button"
        variant="unstyled"
        aria-pressed={to_string(@remote == remote)}
        phx-click="set_workplace"
        phx-value-remote={to_string(remote)}
        class={[
          "flex cursor-pointer items-center gap-1.5 rounded-[3px] px-2.5 py-1 text-sm/[normal] font-medium transition-colors",
          if(@remote == remote,
            do: "bg-white text-black shadow-[0_1px_2px_0_rgb(0_0_0/0.08)]",
            else: "text-grey-600 hover:text-grey-900"
          )
        ]}
      >
        <.presence_dot status={if remote, do: :remote, else: :office} />{label}
      </.button>
    </div>
    """
  end

  # A running session shows its workplace on the switch; the last one names it,
  # since Start continues there.
  defp session_summary(session, opts \\ []) do
    parts = [session.title, session.project.name]

    if opts[:with_workplace],
      do:
        Enum.join(
          parts ++ [status_label(if(session.is_remote, do: :remote, else: :office))],
          " · "
        ),
      else: Enum.join(parts, " · ")
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

  @doc """
  Who works today, for the member's own layer: the first five working people
  with their avatars and where they work, the rest of them behind "show more",
  and the others folded into one row of avatars that unfolds in place.
  """
  attr :presence, :list,
    required: true,
    doc: "from `Firmowid.Timetracker.Session.team_presence/2`"

  def team_today(assigns) do
    {working, absent} = Enum.split_with(assigns.presence, &(&1.status in [:office, :remote]))
    assigns = assign(assigns, working: working, absent: absent, folded: 5)

    ~H"""
    <section id="inbox-team" class="flex flex-col gap-3.5 rounded-sm bg-white p-5">
      <div class="flex items-center justify-between gap-2">
        <h2 class="text-caps-sm font-medium text-grey-600 uppercase">
          {gettext("Today at the company")}
        </h2>
        <span class="text-sm/[1.35] text-grey-700 tabular-nums">
          {gettext("%{working} of %{count} working",
            working: length(@working),
            count: length(@presence)
          )}
        </span>
      </div>
      <ul :if={@working != []} id="inbox-team-working" class="flex flex-col gap-3">
        <li
          :for={{person, i} <- Enum.with_index(@working)}
          data-more={i >= @folded}
          hidden={i >= @folded}
          class="flex items-center gap-2.5"
        >
          <span class="relative shrink-0">
            <.initials person={person} class="size-8 bg-teal-200 text-teal-800" />
            <span class="absolute -right-0.5 -bottom-0.5 flex rounded-full bg-white p-px">
              <.presence_dot status={person.status} />
            </span>
          </span>
          <span class="min-w-0 flex-1 truncate text-sm/[normal] font-medium text-black">
            {person_name(person)}
          </span>
          <span class="sr-only">{status_label(person.status)}</span>
        </li>
      </ul>
      <.button
        :if={length(@working) > @folded}
        type="button"
        variant="unstyled"
        id="inbox-team-more"
        aria-expanded="false"
        aria-controls="inbox-team-working"
        phx-click={
          JS.toggle_attribute({"hidden", ""}, to: "#inbox-team-working [data-more]")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        class="group flex w-full cursor-pointer items-center justify-between gap-2.5 text-left text-sm/[1.35] text-grey-700 hover:text-grey-900"
      >
        <span class="group-aria-expanded:hidden">
          {ngettext(
            "Show %{count} more person",
            "Show %{count} more people",
            length(@working) - @folded
          )}
        </span>
        <span class="hidden group-aria-expanded:inline">{gettext("Collapse")}</span>
        <Lucideicons.chevron_down
          class="size-4 shrink-0 transition-transform group-aria-expanded:rotate-180"
          aria-hidden="true"
        />
      </.button>
      <div :if={@working != [] and @absent != []} class="h-px bg-grey-100"></div>
      <div :if={@absent != []} class="flex flex-col gap-3">
        <.button
          type="button"
          variant="unstyled"
          id="inbox-team-fold"
          aria-expanded="false"
          aria-controls="inbox-team-absent"
          phx-click={
            JS.toggle_attribute({"hidden", ""}, to: "#inbox-team-absent")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
          class="group flex w-full cursor-pointer items-center gap-2.5 text-left text-sm/[1.35] text-grey-700 hover:text-grey-900"
        >
          <span class="isolate flex shrink-0 items-center" aria-hidden="true">
            <.initials
              :for={{person, i} <- Enum.with_index(Enum.take(@absent, 4))}
              person={person}
              class="-mr-1.5 size-7 border-2 border-white bg-grey-200 text-grey-700"
              style={"z-index: #{5 - i}"}
            />
            <span
              :if={length(@absent) > 4}
              class="flex size-7 items-center justify-center rounded-full border-2 border-white bg-grey-100 text-caps-sm font-semibold text-grey-700"
            >
              +{length(@absent) - 4}
            </span>
          </span>
          <span class="min-w-0 flex-1">
            {ngettext(
              "%{count} person is not working",
              "%{count} people are not working",
              length(@absent)
            )}
          </span>
          <Lucideicons.chevron_down
            class="size-4 shrink-0 transition-transform group-aria-expanded:rotate-180"
            aria-hidden="true"
          />
        </.button>
        <ul id="inbox-team-absent" hidden class="flex flex-col gap-3">
          <li :for={person <- @absent} class="flex items-center gap-2.5">
            <.initials person={person} class="size-7 bg-grey-200 text-grey-700" />
            <span class="min-w-0 flex-1 truncate text-sm/[normal] text-grey-700">
              {person_name(person)}
            </span>
            <span class="sr-only">{status_label(person.status)}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :person, :map, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  defp initials(assigns) do
    ~H"""
    <span
      class={[
        "flex shrink-0 items-center justify-center rounded-full text-caps-sm font-semibold uppercase",
        @class
      ]}
      aria-hidden="true"
      {@rest}
    >
      {person_initials(@person)}
    </span>
    """
  end

  defp person_initials(%{name: name}) when is_binary(name) do
    name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)
  end

  defp person_initials(_person), do: "?"

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

  @doc """
  The member's recorded time this month, as one large figure next to the icon
  of the calendar season, in the season's colours.
  """
  attr :duration, :integer, required: true, doc: "session seconds from Session.month_duration/2"
  attr :today, Date, required: true

  def personal_month(assigns) do
    {icon, color, icon_color} = season(assigns.today)
    assigns = assign(assigns, icon: icon, color: color, icon_color: icon_color)

    ~H"""
    <section
      id="inbox-personal-month"
      class="relative flex flex-col gap-2 rounded-sm bg-white p-5 pr-18"
    >
      <h2 class={["text-caps-sm/[normal] font-medium uppercase", @color]}>
        {Firmowid.Cldr.Date.to_string!(@today, format: "LLLL")} · {gettext("Hours worked")}
      </h2>
      <p class="text-lg leading-[normal] font-medium text-black tabular-nums">
        {hours_and_minutes(@duration)}
      </p>
      <Lucideicons.render!
        name={@icon}
        class={["absolute top-1/2 right-5 size-10 -translate-y-1/2 stroke-[0.9]", @icon_color]}
        aria-hidden="true"
      />
    </section>
    """
  end

  # Calendar seasons as counted in Poland: spring from 21 March, summer from
  # 22 June, autumn from 23 September, winter from 22 December.
  defp season(%Date{month: month, day: day}) do
    case {month, day} do
      day_of_year when day_of_year >= {12, 22} or day_of_year < {3, 21} ->
        {"snowflake", "text-teal-700", "text-teal-700"}

      day_of_year when day_of_year < {6, 22} ->
        {"sprout", "text-moss-700", "text-moss-700"}

      day_of_year when day_of_year < {9, 23} ->
        {"sun", "text-rust-700", "text-rust-500"}

      _autumn ->
        {"leaf", "text-rust-700", "text-rust-700"}
    end
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
