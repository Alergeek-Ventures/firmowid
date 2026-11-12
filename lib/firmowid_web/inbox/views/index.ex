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
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Inbox.Components.Queue
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.LeaveRequest
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Assistant.Utilities.Navigation, as: AssistantNavigation
  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Inbox.Utilities.Queue

  # Items a group shows before "Show N more".
  @folded 5

  @impl true
  def mount(_params, _session, socket) do
    if flag_enabled?(:inbox, socket.assigns) do
      {:ok,
       assign(socket,
         page_title: pgettext("sidebar", "Inbox"),
         # The page sets its own padding (32px top and bottom, 40px at the sides).
         no_padding: true,
         items: [],
         fresh: MapSet.new(),
         query: "",
         expanded: MapSet.new()
       )}
    else
      {:ok, push_navigate(socket, to: ~p"/fakturowanie")}
    end
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
        else: assign(socket, query: "", expanded: MapSet.new())

    {:noreply, socket |> assign(:fresh, MapSet.new()) |> load(layer)}
  end

  # Something the inbox shows changed elsewhere (see `FirmowidWeb.Inbox.Hooks.LiveQueue`).
  @impl true
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

    assign(socket,
      layer: layer,
      today: today,
      items: Queue.items(layer, scope, socket.assigns.current_org, today),
      presence: Session.team_presence!(today, scope: scope)
    )
  end

  @impl true
  def handle_event("toggle_group", %{"tier" => tier}, socket) do
    tier = Enum.find([:urgent, :people, :personal, :books], &(Atom.to_string(&1) == tier))

    expanded =
      if tier in socket.assigns.expanded,
        do: MapSet.delete(socket.assigns.expanded, tier),
        else: MapSet.put(socket.assigns.expanded, tier)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("search", %{"q" => query}, socket), do: {:noreply, assign(socket, :query, String.trim(query))}

  def handle_event("decide_item", %{"id" => id, "decision" => action}, socket) do
    decision =
      with true <- flag_enabled?(:inbox, socket.assigns),
           %{actor: %{member: %{role: :admin}}} <- socket.assigns.ash_scope,
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

  # A second click that arrives before the page shows the first one's result.
  def handle_event(event, _params, socket) when event in ["start_session", "stop_session"], do: {:noreply, socket}

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

  defp refresh_queue(socket) do
    send_update(SidebarNav, id: SidebarNav.id(), refresh: true)

    %{layer: layer, ash_scope: scope, current_org: organization, today: today} = socket.assigns
    {:noreply, assign(socket, :items, Queue.items(layer, scope, organization, today))}
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
    assigns = assign(assigns, shown: matching(assigns.items, assigns.query), folded: @folded)

    ~H"""
    <%!-- Dissolves in when the layer changes (see the sidebar's LayerSwitch hook). --%>
    <div
      data-layer-dissolve
      class="@container flex w-full flex-col gap-6 px-4 py-6 md:px-10 md:py-8"
    >
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div class="flex min-w-0 flex-col gap-1">
          <p class="text-sm text-grey-600">
            {if @layer == :company, do: @current_org.display_name, else: gettext("Your matters")} · {Firmowid.Cldr.Date.to_string!(
              @today,
              format: :full
            )}
          </p>
          <h1 class="text-3xl font-bold text-black">{greeting(@items)}</h1>
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
            variant="secondary"
            class="shrink-0"
          >
            <Lucideicons.message_square aria-hidden="true" />{gettext("Ask Firmowid")}
          </.link>
        </div>
      </header>
      <%!-- With nothing waiting, the empty state stretches to end where the side panel ends. --%>
      <div class={[
        "grid grid-cols-1 gap-6 @3xl:grid-cols-[minmax(0,1fr)_20rem]",
        if(@items == [], do: "items-stretch", else: "items-start")
      ]}>
        <div id="inbox-queue" class="flex min-w-0 flex-col gap-7">
          <.all_done :if={@items == []} class="h-full justify-center" />
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
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".SmoothHeight">
          // Animates a card from its old height to its new one when rows are
          // unfolded, folded, resolved or arrive live; rows that arrive fade in.
          export default {
            mounted() {
              this.remember()
              this.onResize = () => this.remember()
              window.addEventListener("resize", this.onResize)
              this.observer = new MutationObserver((mutations) => this.changed(mutations))
              this.observer.observe(this.el, { childList: true })
            },
            destroyed() {
              window.removeEventListener("resize", this.onResize)
              this.observer.disconnect()
            },
            remember() {
              this.height = this.el.getBoundingClientRect().height
            },
            changed(mutations) {
              const from = this.height
              this.remember()
              if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
              if (Math.abs(this.height - from) < 1) return
              const timing = { duration: 250, easing: "cubic-bezier(0.23, 1, 0.32, 1)" }
              this.el.animate([{ height: `${from}px` }, { height: `${this.height}px` }], timing)
              mutations
                .flatMap((mutation) => [...mutation.addedNodes])
                .filter((node) => node.nodeType === Node.ELEMENT_NODE)
                .forEach((node) => node.animate([{ opacity: 0 }, { opacity: 1 }], timing))
            }
          }
        </script>
        <%!-- Starts level with the first card, below its group header (18px + 12px gap). --%>
        <aside class={["flex flex-col gap-2.5", @items != [] && "@3xl:mt-7.75"]}>
          <%!-- A session still running stays stoppable after hourly billing is turned off. --%>
          <.session_panel
            :if={@layer == :me and (@current_org.bills_hourly or not is_nil(@session))}
            session={@session}
            last_session={@last_session}
          />
          <.personal_month :if={@layer == :me} duration={@month_duration} />
          <.month_list :if={@month != []} month={@month} />
          <.office_panel
            :if={@presence != []}
            presence={@presence}
            fit_to={@items != [] && "inbox-queue"}
          />
        </aside>
      </div>
    </div>
    """
  end

  defp matching(items, ""), do: items

  defp matching(items, query) do
    query = String.downcase(query)

    Enum.filter(items, fn item ->
      [item.title, item.person, item.context, Map.get(item, :date_range)]
      |> Enum.reject(&is_nil/1)
      |> Enum.any?(&(&1 |> String.downcase() |> String.contains?(query)))
    end)
  end

  defp greeting([]), do: gettext("All done")

  defp greeting(items) do
    case Enum.count(items, &(&1.tier == :urgent)) do
      0 -> ngettext("%{count} item is waiting", "%{count} items are waiting", length(items))
      urgent -> ngettext("%{count} urgent item", "%{count} urgent items", urgent)
    end
  end
end
