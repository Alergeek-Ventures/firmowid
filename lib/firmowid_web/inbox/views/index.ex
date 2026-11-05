defmodule FirmowidWeb.Inbox.Views.Index do
  @moduledoc """
  The inbox: things that need attention, most important first, next to the
  running session or this month's numbers.

  `?warstwa=ty` shows the member's own layer instead of the company's; members
  without the company layer always see their own.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Inbox.Components.Queue
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Timetracker.Session
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
          assign(socket, month: Queue.month(scope, today), session: nil)

        :me ->
          {:ok, session} = Session.get_current(scope: scope, load: [:project])
          assign(socket, month: [], session: session)
      end

    {:noreply, assign(socket, layer: layer, today: today, items: Queue.items(layer, scope))}
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
          <.session_panel :if={@layer == :me} session={@session} />
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
