defmodule FirmowidWeb.Inbox.Views.Index do
  @moduledoc """
  The inbox: things that need attention, most important first, next to the
  member's session, who works today (for administrators) and this month's
  numbers. The session is started and stopped right here.

  `?warstwa=ty` shows the member's own layer instead of the company's; members
  without the company layer always see their own.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Inbox.Components.Queue
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

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
          assign(socket, month: Queue.month(scope, today), session: nil, last_session: nil)

        :me ->
          {:ok, session} = Session.get_current(scope: scope, load: [:project])

          {:ok, last_session} =
            Session.most_recent(scope: scope, not_found_error?: false, load: [:project])

          assign(socket, month: [], session: session, last_session: last_session)
      end

    presence =
      if socket.assigns.current_user.member.role == :admin,
        do: Session.team_presence!(today, scope: scope),
        else: []

    {:noreply,
     assign(socket,
       layer: layer,
       today: today,
       items: Queue.items(layer, scope),
       presence: presence
     )}
  end

  @impl true
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
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-8 py-4">
      <header class="flex flex-col gap-1">
        <p class="text-sm text-grey-500">
          {if @layer == :company, do: @current_org.name, else: gettext("Your matters")} · {Firmowid.Cldr.Date.to_string!(
            @today,
            format: :long
          )}
        </p>
        <h1 class="text-2xl font-semibold text-grey-900">{greeting(@items)}</h1>
      </header>
      <div class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <div class="flex min-w-0 flex-col gap-8">
          <.all_done :if={@items == []} />
          <section :for={{tier, items} <- Queue.by_tier(@items)} class="flex flex-col gap-3">
            <.tier_header tier={tier} count={length(items)} />
            <div class="overflow-hidden rounded-md bg-white">
              <.item_row :for={item <- items} item={item} />
            </div>
          </section>
        </div>
        <aside class="flex flex-col gap-4 lg:sticky lg:top-8">
          <.session_panel :if={@layer == :me} session={@session} last_session={@last_session} />
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
