defmodule FirmowidWeb.Inbox.Components.SidebarNav do
  @moduledoc """
  The top of the sidebar: the layer switch, the inbox and Czasośledź, with the
  number of waiting company items and whether the member's session runs.

  It lives in the layout of every page, so the numbers load after the page
  connects instead of delaying it. The inbox asks for a refresh after starting
  or stopping the session.
  """

  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Inbox.Components.Sidebar, only: [label_styles: 0]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Inbox.Utilities.Queue

  @doc "The DOM and component id, for `send_update/3`."
  @spec id() :: String.t()
  def id, do: "app-sidebar-nav"

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, load_status(socket)}

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns[:status], do: socket, else: load_status(socket))}
  end

  defp load_status(socket) do
    scope = socket.assigns.scope

    assign_async(socket, :status, fn ->
      {:ok, session} = Session.get_current(scope: scope)
      {:ok, %{status: %{company: length(Queue.attention_items(scope)), running?: session != nil}}}
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        company_count: if(assigns.status.ok?, do: assigns.status.result.company, else: 0),
        running?: assigns.status.ok? and assigns.status.result.running?
      )

    ~H"""
    <nav id={@id} class="flex flex-col gap-0.5" aria-label={pgettext("sidebar", "Main")}>
      <%!--
        Both layers when expanded; collapsed, only the way to the other layer,
        so the switch keeps its height and nothing below it moves. Its buttons
        stay hidden while the sidebar resizes and fade in once it has settled.
      --%>
      <div
        :if={@layered?}
        class="mb-2 grid h-10 grid-cols-2 gap-1 overflow-clip rounded-full bg-grey-800 p-1 md:in-data-[sidebar=collapsed]:grid-cols-1"
        role="group"
        aria-label={pgettext("sidebar", "Layer")}
      >
        <.link
          :for={{layer, icon} <- [company: "building-2", me: "user"]}
          kind="unstyled"
          navigate={Navigation.inbox_path(layer)}
          aria-current={@layer == layer && "page"}
          title={layer_label(layer)}
          class={[
            "relative flex h-8 min-w-0 items-center justify-center gap-2 rounded-full font-medium transition-[color,background-color,opacity] duration-150 in-data-sidebar-moving:opacity-0 in-data-sidebar-moving:duration-0",
            if(@layer == layer,
              do: "bg-white text-black md:in-data-[sidebar=collapsed]:hidden",
              else: "text-white/60 hover:text-white"
            )
          ]}
        >
          <Lucideicons.render!
            name={icon}
            class="hidden size-5 shrink-0 md:in-data-[sidebar=collapsed]:block"
            aria-hidden="true"
          />
          <span class="truncate md:in-data-[sidebar=collapsed]:sr-only">{layer_label(layer)}</span>
          <.count
            :if={layer == :company and @layer != :company}
            count={@company_count}
            class="bg-grey-700 text-white md:in-data-[sidebar=collapsed]:-top-1 md:in-data-[sidebar=collapsed]:-right-1"
          />
        </.link>
      </div>
      <.button
        id="app-search-open"
        variant="unstyled"
        type="button"
        phx-click={JS.dispatch("firmowid:search", to: "#app-search")}
        class={link_styles(false)}
        title={gettext("Search")}
        aria-haspopup="dialog"
        aria-controls="app-search-modal"
      >
        <Lucideicons.search class="size-5 shrink-0" aria-hidden="true" />
        <span class={label_styles()}>
          <span class="flex items-center justify-between gap-2">
            {gettext("Search")}
            <kbd data-search-shortcut class="text-xs text-white/70">Ctrl K</kbd>
          </span>
        </span>
      </.button>
      <.link
        kind="unstyled"
        navigate={@inbox.path}
        aria-current={@current_id == :inbox && "page"}
        title={@inbox.label}
        class={link_styles(@current_id == :inbox)}
      >
        <Lucideicons.render! name={@inbox.icon} class="size-5 shrink-0" aria-hidden="true" />
        <span class={label_styles()}>{@inbox.label}</span>
        <%!-- Clear of the 20 px icon, so the badge hides little of it. --%>
        <.count
          :if={@layer == :company}
          count={@company_count}
          class="bg-white text-black md:in-data-[sidebar=collapsed]:-top-1.5 md:in-data-[sidebar=collapsed]:-right-2"
        />
      </.link>
      <.link
        :if={@layer == :me}
        kind="unstyled"
        navigate={@timetracker.path}
        aria-current={@current_id == :timetracker && "page"}
        title={@timetracker.label}
        class={link_styles(@current_id == :timetracker)}
      >
        <Lucideicons.render! name={@timetracker.icon} class="size-5 shrink-0" aria-hidden="true" />
        <span class={label_styles()}>{@timetracker.label}</span>
        <span
          :if={@running?}
          class="size-2 shrink-0 animate-pulse rounded-full bg-moss-400 md:in-data-[sidebar=collapsed]:absolute md:in-data-[sidebar=collapsed]:top-0.5 md:in-data-[sidebar=collapsed]:right-0.5"
          title={gettext("The session is running")}
        ></span>
      </.link>
    </nav>
    """
  end

  attr :count, :integer, required: true
  attr :class, :any, required: true

  # Its own line height, not the 20 px rows; collapsed, it moves to the icon's
  # corner, placed by the caller.
  defp count(assigns) do
    ~H"""
    <span
      :if={@count > 0}
      class={[
        "rounded-full px-1.5 text-xs/normal font-medium tabular-nums md:in-data-[sidebar=collapsed]:absolute",
        @class
      ]}
    >
      {@count}
    </span>
    """
  end

  defp layer_label(:company), do: pgettext("sidebar layer", "Company")
  defp layer_label(:me), do: pgettext("sidebar layer", "You")

  # Same as the other sidebar links; relative for the corner badge when collapsed.
  defp link_styles(active?) do
    [
      "relative flex w-full items-center gap-3 rounded-md px-1.5 py-1.5 text-left leading-5 transition-colors hover:bg-grey-700/50",
      if(active?, do: "bg-grey-700/70 text-white", else: "text-white/70")
    ]
  end
end
