defmodule FirmowidWeb.Inbox.Views.Index do
  @moduledoc """
  The inbox: things that need attention, most important first, next to the
  member's session, who works today and this month's
  numbers. The session is started and stopped right here.

  `?warstwa=ty` shows the member's own layer instead of the company's; members
  without the company layer always see their own.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidWeb.Inbox.Components.Queue
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.LeaveRequest
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Inbox.Utilities.Queue

  @impl true
  def mount(_params, _session, socket) do
    if flag_enabled?(:inbox, socket.assigns) do
      {:ok, assign(socket, :page_title, pgettext("sidebar", "Inbox"))}
    else
      {:ok, push_navigate(socket, to: ~p"/fakturowanie")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.ash_scope
    today = socket.assigns.timezone |> DateTime.now!() |> DateTime.to_date()

    layer =
      if socket.assigns.current_user.member.role == :employee,
        do: :me,
        else: Navigation.parse_layer(params["warstwa"])

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

    presence = Session.team_presence!(today, scope: scope)

    {:noreply,
     assign(socket,
       layer: layer,
       today: today,
       items: Queue.items(layer, scope, today),
       presence: presence
     )}
  end

  @impl true
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

    %{layer: layer, ash_scope: scope, today: today} = socket.assigns
    {:noreply, assign(socket, :items, Queue.items(layer, scope, today))}
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
    ~H"""
    <%!-- Dissolves in when the layer changes (see the sidebar's LayerSwitch hook). --%>
    <div data-layer-dissolve class="mx-auto flex w-full max-w-6xl flex-col gap-8 py-4">
      <header class="flex flex-col gap-1">
        <p class="text-sm text-grey-500">
          {if @layer == :company, do: @current_org.name, else: gettext("Your matters")} · {Firmowid.Cldr.Date.to_string!(
            @today,
            format: :long
          )}
        </p>
        <h1 class="text-2xl font-semibold text-grey-900">{greeting(@items)}</h1>
      </header>
      <div class="grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <div class="flex min-w-0 flex-col gap-8">
          <.all_done :if={@items == []} />
          <section :for={{tier, items} <- Queue.by_tier(@items)} class="flex flex-col gap-3">
            <.tier_header tier={tier} count={length(items)} />
            <div class="overflow-hidden rounded-md bg-white">
              <.item_row
                :for={item <- if(tier == :books, do: Enum.take(items, 5), else: items)}
                item={item}
              />
              <%!-- The rest of the overdue invoices, revealed in place: the invoice list only shows one month. --%>
              <div :if={tier == :books and length(items) > 5} id="inbox-books-rest" class="hidden">
                <.item_row :for={item <- Enum.drop(items, 5)} item={item} />
              </div>
            </div>
            <.button
              :if={tier == :books and length(items) > 5}
              type="button"
              size="small"
              variant="ghost"
              class="self-end"
              phx-click={JS.remove_class("hidden", to: "#inbox-books-rest") |> JS.hide()}
            >
              {gettext("Show all (%{count})", count: length(items))}
              <Lucideicons.chevron_down class="size-4" aria-hidden="true" />
            </.button>
          </section>
        </div>
        <%!-- Starts level with the first card of the queue, below its tier heading (18px + 12px gap). --%>
        <aside class={["flex flex-col gap-4 lg:sticky lg:top-8", @items != [] && "lg:mt-7.5"]}>
          <.session_panel :if={@layer == :me} session={@session} last_session={@last_session} />
          <.personal_month :if={@layer == :me} duration={@month_duration} />
          <.office_panel :if={@presence != []} presence={@presence} />
          <.month_list :if={@month != []} month={@month} />
        </aside>
      </div>
    </div>
    """
  end

  defp greeting([]), do: gettext("All done")

  defp greeting(items) do
    case Enum.count(items, &(&1.tier == :urgent)) do
      0 -> ngettext("%{count} item is waiting", "%{count} items are waiting", length(items))
      urgent -> ngettext("%{count} urgent item", "%{count} urgent items", urgent)
    end
  end
end
