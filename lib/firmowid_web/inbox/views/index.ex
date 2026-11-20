defmodule FirmowidWeb.Inbox.Views.Index do
  @moduledoc """
  The inbox: things that need attention, most important first, next to the
  member's session, who works today and this month's
  numbers. The session is started and stopped right here.

  `?warstwa=ty` shows the member's own layer instead of the company's; members
  without the company layer always see their own.

  Each group shows five items and unfolds the rest in place; what is unfolded
  holds while the page stays open, live updates included, and resets when the
  layer changes. The search narrows the groups to matching items.

  Any item but an urgent one can be put aside for the whole company, for some
  days or for good (`Firmowid.Core.InboxSnooze`). Those put aside until a day
  are counted next to the title, which opens their list: there each can be
  brought back at once or removed for good. Every such step can be undone from
  its toast.

  Under the company's queue sit the actions the organization does most often
  (`FirmowidWeb.Inbox.Utilities.Shortcuts`); a cost invoice from outside KSeF
  is uploaded right from its tile.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Inbox.Components.Queue
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [guard_upload_progress: 2]
  import Phoenix.Component, except: [link: 1]

  alias Ash.Notifier.Notification
  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.LeaveRequest
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Assistant.Utilities.Navigation, as: AssistantNavigation
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Core.Toast
  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Inbox.Utilities.Queue
  alias FirmowidWeb.Inbox.Utilities.Shortcuts
  alias FirmowidWeb.Invoicing.Components.CostInvoiceUpload
  alias Phoenix.Socket.Broadcast

  # Items a group shows before "Show N more".
  @folded 5

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: pgettext("sidebar", "Inbox"),
       # The page sets its own padding (32px top and bottom, 40px at the sides).
       no_padding: true,
       items: [],
       put_aside: [],
       shortcuts: [],
       fresh: MapSet.new(),
       query: "",
       expanded: MapSet.new()
     )
     |> allow_cost_invoice_upload()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    layer =
      if socket.assigns.current_user.member.role == :employee,
        do: :me,
        else: Navigation.parse_layer(params["warstwa"])

    socket =
      if socket.assigns[:layer] == layer,
        do: socket,
        else: assign(socket, query: "", expanded: MapSet.new(), shortcuts: shortcuts(socket, layer))

    # The company layer links to the assistant from its header instead.
    {:noreply,
     socket
     |> assign(fresh: MapSet.new(), hide_floating_assistant: layer == :company)
     |> load(layer)}
  end

  # The upload tile is offered to the members who may add cost invoices; they
  # also see on it the files still on their way and hear when one could not
  # be read.
  defp allow_cost_invoice_upload(socket) do
    if Ash.can?({CostInvoice, :create}, socket.assigns.current_user) do
      if connected?(socket) do
        for event <- ["created", "updated", "destroyed"],
            do: Endpoint.subscribe("blob:#{event}:#{socket.assigns.current_org.id}")
      end

      socket
      |> allow_upload(
        :file,
        [progress: guard_upload_progress(&handle_progress/3, :ash_scope)] ++
          CostInvoiceUpload.upload_options()
      )
      |> CostInvoiceUpload.assign_counts()
    else
      socket
    end
  end

  # What the organization does most often is read once per layer: it does not
  # change while the page stays open.
  defp shortcuts(socket, :company),
    do: Shortcuts.for_company(socket.assigns.ash_scope, socket.assigns.current_org, DateTime.utc_now())

  defp shortcuts(_socket, :me), do: []

  defp handle_progress(:file, _entry, socket) do
    with {[_ | _] = entries, []} <- uploaded_entries(socket, :file),
         true <-
           Enum.any?(CostInvoiceUpload.consume(socket, entries), &match?({:ok, %Blob{}}, &1)) do
      LiveToast.send_toast(
        :info,
        gettext("The files are being processed and will be available in Firmowid in a few moments")
      )
    end

    {:noreply, CostInvoiceUpload.assign_counts(socket)}
  end

  # A file was sent, read or could not be read.
  @impl true
  def handle_info(%Broadcast{payload: %Notification{} = notification}, socket) do
    CostInvoiceUpload.toast_failure(notification)
    {:noreply, CostInvoiceUpload.assign_counts(socket)}
  end

  # Something the inbox shows changed elsewhere (see `FirmowidWeb.Inbox.Hooks.LiveQueue`).
  def handle_info(:inbox_refresh, socket), do: {:noreply, reload(socket)}

  # Overdue invoices and expiring connections change with time alone (see
  # `FirmowidWeb.Inbox.Hooks.LiveQueue`).
  def handle_info(:inbox_tick, socket), do: {:noreply, reload(socket)}

  # Reloads the current layer and marks the items that were not there before,
  # so the page can point them out.
  defp reload(socket) do
    seen = MapSet.new(socket.assigns.items, & &1.id)
    socket = load(socket, socket.assigns.layer)

    assign(
      socket,
      :fresh,
      for(item <- socket.assigns.items, item.id not in seen, into: MapSet.new(), do: item.id)
    )
  end

  defp load(socket, layer) do
    scope = socket.assigns.ash_scope
    today = socket.assigns.timezone |> DateTime.now!() |> DateTime.to_date()

    socket =
      case layer do
        :company ->
          assign(socket,
            month: Queue.month(scope, today),
            month_duration: nil,
            session: nil,
            last_session: nil
          )

        :me ->
          {:ok, session} = Session.get_current(scope: scope, load: [:project])

          {:ok, last_session} =
            Session.most_recent(scope: scope, not_found_error?: false, load: [:project])

          assign(socket,
            month: [],
            month_duration: Session.month_duration!(today, scope: scope),
            session: session,
            last_session: last_session
          )
      end

    socket
    |> assign(layer: layer, today: today, presence: Session.team_presence!(today, scope: scope))
    |> assign_items()
  end

  defp assign_items(socket) do
    %{layer: layer, ash_scope: scope, current_org: organization, today: today} = socket.assigns

    {items, put_aside} =
      layer
      |> Queue.items(scope, organization, today, taxes?: flag_enabled?(:taxes, socket.assigns))
      |> Queue.split_put_aside(scope)

    # Items hidden for good are not listed anywhere.
    assign(socket,
      items: items,
      put_aside: Enum.filter(put_aside, fn {_item, snooze} -> snooze.until end)
    )
  end

  @impl true
  def handle_event("toggle_group", %{"tier" => tier}, socket) do
    tier =
      Enum.find([:urgent, :people, :personal, :books, :info], &(Atom.to_string(&1) == tier))

    expanded =
      if tier in socket.assigns.expanded,
        do: MapSet.delete(socket.assigns.expanded, tier),
        else: MapSet.put(socket.assigns.expanded, tier)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("search", %{"q" => query}, socket), do: {:noreply, assign(socket, :query, String.trim(query))}

  # The files upload on their own; `handle_progress/3` takes them from there.
  # A rejected file (too large or of a wrong type) is dropped with a toast:
  # left in place, it would hold back the files chosen after it.
  def handle_event("upload", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.file.entries, socket, fn
        %{valid?: false} = entry, socket ->
          LiveToast.send_toast(:error, entry.client_name, title: gettext("Failed to upload the file"))

          cancel_upload(socket, :file, entry.ref)

        _entry, socket ->
          socket
      end)

    {:noreply, CostInvoiceUpload.assign_counts(socket)}
  end

  # Without `days` the item is put aside for good.
  def handle_event("snooze_item", %{"id" => id} = params, socket) do
    if Enum.any?(socket.assigns.items, &(&1.id == id)) do
      days = params["days"] && String.to_integer(params["days"])
      Core.snooze_inbox_item!(id, days, scope: socket.assigns.ash_scope)
      put_aside_toast(id, days, socket.assigns.today)
    end

    refresh_queue(socket)
  end

  # Brought back from the list of items put aside; undoing puts it aside again
  # until the same day.
  def handle_event("restore_item", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    # Someone else may have brought it back already; the refresh shows the queue as it is.
    case Core.get_inbox_snooze!(id, scope: scope, not_found_error?: false) do
      nil ->
        :ok

      snooze ->
        Core.restore_inbox_item!(snooze, scope: scope)

        restored_toast(id, days_left(snooze.until, socket))
    end

    refresh_queue(socket)
  end

  # Removed from the list of items put aside: it stays hidden for good.
  def handle_event("remove_item", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.put_aside, fn {item, _snooze} -> item.id == id end) do
      nil ->
        :ok

      {_item, snooze} ->
        Core.snooze_inbox_item!(id, nil, scope: socket.assigns.ash_scope)
        removed_toast(id, days_left(snooze.until, socket))
    end

    refresh_queue(socket)
  end

  # From a toast: puts the item back where it was, aside until a day (`days`)
  # or in the queue.
  def handle_event("undo_item", %{"id" => id} = params, socket) do
    scope = socket.assigns.ash_scope

    case params["days"] do
      nil ->
        with %{} = snooze <- Core.get_inbox_snooze!(id, scope: scope, not_found_error?: false),
             do: Core.restore_inbox_item!(snooze, scope: scope)

      days ->
        Core.snooze_inbox_item!(id, String.to_integer(days), scope: scope)
    end

    refresh_queue(socket)
  end

  def handle_event("decide_item", %{"id" => id, "decision" => action}, socket) do
    decision =
      with %{actor: %{member: %{role: :admin}}} <- socket.assigns.ash_scope,
           %{} = item <- Enum.find(socket.assigns.items, &(&1.id == id)) do
        Enum.find(Map.get(item, :decisions, []), &(Atom.to_string(&1.action) == action))
      else
        _ -> nil
      end

    case decision do
      nil ->
        LiveToast.send_toast(
          :info,
          gettext("This request is no longer waiting for a decision.")
        )

        {:noreply, socket}

      %{} ->
        decision
        |> decide(socket.assigns.ash_scope)
        |> decision_changed(socket)
    end
  end

  def handle_event("start_session", _params, %{assigns: %{session: nil, last_session: %{} = last}} = socket) do
    scope = socket.assigns.ash_scope

    case Session.get_current(scope: scope, load: [:project]) do
      # Another tab started one meanwhile: show it instead of starting a second.
      {:ok, %Session{} = running} ->
        session_changed({:ok, running}, socket)

      {:ok, nil} ->
        %{title: last.title, project_id: last.project_id, is_remote: last.is_remote}
        |> Session.start(scope: scope, load: [:project])
        |> session_changed(socket)
    end
  end

  # Stops the session running now, not the one this page loaded: another tab or
  # the auto-stop may have ended it, and stopping it again would move its end.
  def handle_event("stop_session", _params, %{assigns: %{session: %{}}} = socket) do
    [scope: socket.assigns.ash_scope]
    |> Session.stop_current()
    |> session_changed(socket)
  end

  # Changes the session running now: another tab or the auto-stop may have
  # ended the one this page shows, and a finished session keeps its workplace.
  def handle_event("set_workplace", %{"remote" => remote}, %{assigns: %{session: %{id: id}}} = socket) do
    scope = socket.assigns.ash_scope

    case Session.get_current(scope: scope, load: [:project]) do
      {:ok, %Session{id: ^id} = running} ->
        # The project stays the same, so the loaded one carries over.
        result =
          with {:ok, updated} <-
                 Session.edit_current_user_session(%{id: id, is_remote: remote == "true"},
                   scope: scope
                 ) do
            {:ok, %{updated | project: running.project}}
          end

        session_changed(result, socket)

      {:ok, other} ->
        session_changed({:ok, other}, socket)
    end
  end

  # A second click that arrives before the page shows the first one's result.
  def handle_event(event, _params, socket) when event in ["start_session", "stop_session", "set_workplace"],
    do: {:noreply, socket}

  defp decide(%{action: action, record_id: id}, scope) when action in [:accept_leave_request, :decline_leave_request] do
    case Timetracker.get_leave_request(id, scope: scope, not_found_error?: false) do
      {:ok, %LeaveRequest{status: :pending}} ->
        case action do
          :accept_leave_request -> Timetracker.accept_leave_request(id, scope: scope)
          :decline_leave_request -> Timetracker.decline_leave_request(id, scope: scope)
        end

      {:ok, _decided_or_deleted} ->
        :stale

      {:error, error} ->
        {:error, error}
    end
  end

  defp decision_changed({:ok, %LeaveRequest{status: status}}, socket) do
    message =
      case status do
        :accepted -> gettext("The request has been approved.")
        :declined -> gettext("The request has been rejected.")
      end

    LiveToast.send_toast(:info, message)
    refresh_queue(socket)
  end

  defp decision_changed(:stale, socket) do
    LiveToast.send_toast(
      :info,
      gettext("This request is no longer waiting for a decision.")
    )

    refresh_queue(socket)
  end

  defp decision_changed({:error, _error}, socket) do
    LiveToast.send_toast(
      :error,
      gettext("Could not save the decision. Open the request and try again.")
    )

    {:noreply, socket}
  end

  # Days until a snooze ends, counted in the organization's days, so putting
  # the item aside again brings it back on the same day; as text, like the
  # menu's `days`.
  defp days_left(until, socket), do: days_left(until, socket.assigns.today, socket.assigns.timezone)

  @doc false
  @spec days_left(DateTime.t(), Date.t(), String.t()) :: String.t()
  def days_left(until, today, timezone) do
    until
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
    |> Date.diff(today)
    |> max(1)
    |> to_string()
  end

  @doc """
  Toast after putting an item aside until a day, or after removing it for good
  without `days` (red and longer, like `removed_toast/2`).
  """
  @spec put_aside_toast(String.t(), pos_integer() | nil, Date.t()) :: String.t()
  def put_aside_toast(id, nil, _today), do: undo_toast(gettext("Item removed"), %{id: id}, :error, 10_000)

  def put_aside_toast(id, days, today),
    do:
      undo_toast(gettext("Item put aside until %{date}", date: Queue.short_date(Date.add(today, days), today)), %{id: id})

  @doc "Toast after bringing back an item that was aside for `days` more."
  @spec restored_toast(String.t(), String.t()) :: String.t()
  def restored_toast(id, days), do: undo_toast(gettext("Item is back in the inbox"), %{id: id, days: days})

  @doc """
  Toast after removing for good an item that was aside for `days` more: red,
  and it stays longer, as only its undo can bring the item back.
  """
  @spec removed_toast(String.t(), String.t()) :: String.t()
  def removed_toast(id, days), do: undo_toast(gettext("Item removed"), %{id: id, days: days}, :error, 10_000)

  # The undo goes back through the page (`undo_item`) and closes the toast.
  # LiveToast shows a toast for 6 seconds unless told otherwise.
  defp undo_toast(message, value, kind \\ :info, duration \\ nil) do
    LiveToast.send_toast(kind, message,
      duration: duration,
      action: fn assigns ->
        assigns = assign(assigns, :value, value)

        ~H"""
        <Toast.undo_action on_click={JS.push("undo_item", value: @value)} />
        """
      end
    )
  end

  defp refresh_queue(socket) do
    send_update(SidebarNav, id: SidebarNav.id(), refresh: true)

    {:noreply, assign_items(socket)}
  end

  # Reloads the page and the sidebar, which shows whether the session runs; the
  # session is assigned right away so a repeated click is ignored. A submitted
  # hours record or a project the member left blocks the change; the session
  # form in Czasośledź explains those.
  defp session_changed({:ok, session}, socket) do
    send_update(SidebarNav, id: SidebarNav.id(), refresh: true)

    {:noreply,
     socket
     |> assign(:session, if(session && is_nil(session.end_datetime), do: session))
     |> push_patch(to: Navigation.inbox_path(socket.assigns.layer))}
  end

  defp session_changed({:error, %error{}}, socket) when error in [Ash.Error.Forbidden, Ash.Error.Invalid] do
    LiveToast.send_toast(
      :error,
      gettext("The session could not be changed here. Open Time tracking.")
    )

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        shown: matching(assigns.items, assigns.query),
        folded: @folded,
        # A session still running stays stoppable after hourly billing is turned off.
        session?:
          assigns.layer == :me and
            (assigns.current_org.bills_hourly or not is_nil(assigns.session))
      )

    ~H"""
    <%!-- Dissolves in when the layer changes (see the sidebar's LayerSwitch hook). --%>
    <div
      data-layer-dissolve
      class="@container flex w-full flex-col gap-6 px-4 py-6 md:px-10 md:py-8"
    >
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div class="flex min-w-0 flex-col">
          <p class="text-sm/[1.35] text-grey-600">
            {if @layer == :company, do: @current_org.display_name, else: gettext("Your matters")} · {Firmowid.Cldr.Date.to_string!(
              @today,
              format: :full
            )}
          </p>
          <div class="flex flex-wrap items-baseline gap-x-3">
            <h1 class="text-3xl leading-[normal] font-bold text-black">{greeting(@items)}</h1>
            <.put_aside_link :if={@put_aside != []} count={length(@put_aside)} />
          </div>
        </div>
        <div class="flex items-center gap-4 max-md:w-full">
          <form phx-change="search" phx-submit="search" class="w-70 max-md:min-w-0 max-md:flex-1">
            <.search_field
              id="inbox-search"
              name="q"
              value={@query}
              placeholder={gettext("Search the inbox")}
              size="small"
              autocomplete="off"
              phx-debounce="200"
            />
          </form>
          <.link
            kind="button"
            navigate={AssistantNavigation.page_path()}
            size="small"
            variant="tertiary"
            class="shrink-0"
          >
            <Lucideicons.message_square aria-hidden="true" />{gettext("Ask Firmowid")}
          </.link>
        </div>
      </header>
      <%!-- With nothing waiting, the empty state stretches to end where the side panel ends. --%>
      <div
        id="inbox-columns"
        phx-hook=".SessionPlacement"
        class={[
          "group/columns grid grid-cols-1 gap-6 @3xl:grid-cols-[minmax(0,1fr)_20rem] @3xl:gap-x-12",
          if(@items == [], do: "items-stretch", else: "items-start")
        ]}
      >
        <%!-- The member's session closes their queue; with nothing waiting it starts level with the side panel. --%>
        <div
          id="inbox-queue"
          class={[
            "flex min-w-0 flex-col",
            if(@layer == :me, do: "gap-4", else: "gap-7"),
            @items == [] && @session? && "@3xl:mt-7.75"
          ]}
        >
          <.all_done :if={@items == [] and not @session?} class="flex-1 justify-center" />
          <p
            :if={@items != [] and @shown == []}
            class="rounded-sm bg-white px-5 py-4 text-sm text-grey-600"
          >
            {gettext("No items match your search.")}
          </p>
          <section
            :for={{tier, items} <- Queue.by_tier(@shown)}
            id={"inbox-group-#{tier}"}
            class="flex flex-col gap-3"
          >
            <.tier_header tier={tier} count={length(items)} />
            <div
              id={"inbox-group-#{tier}-list"}
              phx-hook=".SmoothHeight"
              class="overflow-hidden rounded-sm bg-white"
            >
              <.item_row
                :for={item <- if(tier in @expanded, do: items, else: Enum.take(items, @folded))}
                item={item}
                fresh={item.id in @fresh}
                today={@today}
              />
              <.button
                :if={length(items) > @folded}
                type="button"
                variant="unstyled"
                id={"inbox-group-#{tier}-toggle"}
                aria-expanded={to_string(tier in @expanded)}
                aria-controls={"inbox-group-#{tier}"}
                phx-click="toggle_group"
                phx-value-tier={tier}
                class="flex w-full cursor-pointer items-center justify-end gap-1 px-5 py-3 text-sm font-medium text-grey-700 transition-colors hover:bg-grey-50 hover:text-grey-900 max-md:px-4"
              >
                <%= if tier in @expanded do %>
                  {gettext("Collapse")}<Lucideicons.chevron_up class="size-4" aria-hidden="true" />
                <% else %>
                  {gettext("Show %{count} more", count: length(items) - @folded)}<Lucideicons.chevron_down
                    class="size-4"
                    aria-hidden="true"
                  />
                <% end %>
              </.button>
            </div>
          </section>
          <.shortcuts
            :if={@shortcuts != []}
            shortcuts={@shortcuts}
            upload={assigns[:uploads][:file]}
            uploading={assigns[:currently_uploading_count]}
            processing={assigns[:processing_blobs_count]}
          />
          <.session_panel :if={@session?} session={@session} last_session={@last_session} />
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".SmoothHeight">
          // Animates a card from its old height to its new one when rows are
          // unfolded, folded, resolved or arrive live; rows that arrive fade in.
          //
          // A row put aside or decided here (`inbox:leave`, see the queue's
          // `leave/3`) first dissolves in place; only then is its event sent.
          // When the answer takes it off, the rows under it glide up from where
          // they were, and a folded row that takes the free place slides in
          // from the card's bottom edge.
          const FADE_MS = 200
          const MOVE = { duration: 280, easing: "cubic-bezier(0.23, 1, 0.32, 1)" }
          const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

          export default {
            mounted() {
              this.remember()
              this.onResize = () => this.remember()
              window.addEventListener("resize", this.onResize)
              this.observer = new MutationObserver((mutations) => this.changed(mutations))
              this.observer.observe(this.el, { childList: true })
              this.el.addEventListener("inbox:leave", (event) => this.leave(event.target, event.detail))
            },
            destroyed() {
              window.removeEventListener("resize", this.onResize)
              this.observer.disconnect()
            },
            remember() {
              this.height = this.el.getBoundingClientRect().height
            },
            leave(row, { event, value }) {
              if (this.leaving) return
              if (reducedMotion()) return this.pushEvent(event, value)
              const fade = row.animate(
                [{ opacity: 1, filter: "blur(0)" }, { opacity: 0, filter: "blur(4px)" }],
                { duration: FADE_MS, easing: "ease-out", fill: "forwards" }
              )
              this.leaving = { row, sent: false }
              // A timer rather than the animation's end: a background tab pauses
              // animations, which would hold the event back.
              setTimeout(() => {
                this.leaving.sent = true
                this.pushEvent(event, value, () => {
                  // The answer did not take the row off (it failed): it comes back.
                  if (row.isConnected) fade.cancel()
                  this.leaving = null
                })
              }, FADE_MS)
            },
            // Where every row stands before the answer changes the card.
            beforeUpdate() {
              if (this.leaving?.sent)
                this.tops = new Map([...this.el.children].map((el) => [el, el.getBoundingClientRect().top]))
            },
            changed(mutations) {
              const from = this.height
              this.remember()
              if (reducedMotion()) return
              if (this.tops) return this.glide(from)
              if (Math.abs(this.height - from) < 1) return
              const timing = { duration: 250, easing: "cubic-bezier(0.23, 1, 0.32, 1)" }
              this.el.animate([{ height: `${from}px` }, { height: `${this.height}px` }], timing)
              mutations
                .flatMap((mutation) => [...mutation.addedNodes])
                .filter((node) => node.nodeType === Node.ELEMENT_NODE)
                .forEach((node) => node.animate([{ opacity: 0 }, { opacity: 1 }], timing))
            },
            // FLIP: rows that stayed start where they stood and glide to their
            // new place; rows that arrived start below the card's bottom edge.
            glide(from) {
              const tops = this.tops
              this.tops = null
              if (Math.abs(this.height - from) >= 1)
                this.el.animate([{ height: `${from}px` }, { height: `${this.height}px` }], MOVE)
              for (const el of this.el.children) {
                const top = el.getBoundingClientRect().top
                const delta = tops.has(el) ? tops.get(el) - top : el.getBoundingClientRect().height
                if (Math.abs(delta) < 1) continue
                el.animate([{ transform: `translateY(${delta}px)` }, { transform: "translateY(0)" }], MOVE)
              }
            }
          }
        </script>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".SessionPlacement">
          // Moves the member's session to the side column, in its compact form,
          // when the large card under the queue would end below the first
          // screen. Only with two columns: stacked on phones, it stays under the
          // queue.
          const GAP = 16
          const BOTTOM_GAP = 32

          export default {
            mounted() {
              this.onChange = () => this.place()
              window.addEventListener("resize", this.onChange)
              this.observer = new ResizeObserver(this.onChange)
              this.observer.observe(this.el)
              this.place()
              // Text set in a font that is still loading measures shorter.
              document.fonts.ready.then(() => this.place())
            },
            updated() { this.place() },
            destroyed() {
              window.removeEventListener("resize", this.onChange)
              this.observer.disconnect()
            },
            place() {
              const card = this.el.querySelector("#inbox-session")
              const lists = this.el.querySelectorAll("#inbox-queue > section > [id$=-list]")
              const twoColumns = getComputedStyle(this.el).gridTemplateColumns.split(" ").length > 1
              if (card && card.offsetParent) this.height = card.getBoundingClientRect().height
              let compact = false
              if (card && lists.length && twoColumns && this.el.querySelector("#inbox-session-compact")) {
                // The list's content height is the one it ends at, while rows
                // that arrive or fold still animate its box.
                const list = lists[lists.length - 1]
                const queueBottom = list.getBoundingClientRect().top + list.scrollHeight + window.scrollY
                compact = queueBottom + GAP + (this.height || 260) > window.innerHeight - BOTTOM_GAP
              }
              if (compact === this.el.hasAttribute("data-compact-session")) return
              if (compact) this.js().setAttribute(this.el, "data-compact-session", "")
              else this.js().removeAttribute(this.el, "data-compact-session")
            }
          }
        </script>
        <%!-- Starts level with the first card, below its group header (19px + 12px gap). --%>
        <aside class={["flex flex-col gap-2.5", (@items != [] or @session?) && "@3xl:mt-7.75"]}>
          <.session_panel
            :if={@session? and @items != []}
            session={@session}
            last_session={@last_session}
            compact
          />
          <.personal_month :if={@layer == :me} duration={@month_duration} today={@today} />
          <.month_list :if={@month != []} month={@month} />
          <.team_today :if={@layer == :me and @presence != []} presence={@presence} />
          <.office_panel
            :if={@layer == :company and @presence != []}
            presence={@presence}
            fit_to={@items != [] && "inbox-queue"}
          />
        </aside>
      </div>
      <.put_aside_modal
        :if={@put_aside != []}
        entries={@put_aside}
        today={@today}
        timezone={@timezone}
      />
    </div>
    """
  end

  defp matching(items, ""), do: items

  defp matching(items, query) do
    query = String.downcase(query)

    Enum.filter(items, fn item ->
      [item.title, item.person, item.context, Map.get(item, :date_range), Map.get(item, :amount)]
      |> Enum.reject(&is_nil/1)
      |> Enum.any?(&(&1 |> String.downcase() |> String.contains?(query)))
    end)
  end

  # Items for information only wait for nothing.
  defp greeting(items) do
    case Enum.reject(items, &(&1.tier == :info)) do
      [] -> gettext("All done")
      waiting -> waiting_greeting(waiting)
    end
  end

  defp waiting_greeting(items) do
    case Enum.count(items, &(&1.tier == :urgent)) do
      0 -> ngettext("%{count} item is waiting", "%{count} items are waiting", length(items))
      urgent -> ngettext("%{count} urgent item", "%{count} urgent items", urgent)
    end
  end
end
