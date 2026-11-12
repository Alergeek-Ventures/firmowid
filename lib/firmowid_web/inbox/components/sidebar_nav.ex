defmodule FirmowidWeb.Inbox.Components.SidebarNav do
  @moduledoc """
  The top of the sidebar: the layer switch, the inbox and Czasośledź, with the
  number of all waiting company items on the inbox and whether the member's
  session runs.

  It lives in the layout of every page, so the numbers load after the page
  connects instead of delaying it. Until they arrive it shows the last numbers
  this member saw (kept in the `:sidebar_status` cache), so a company badge
  stays put across pages and only fades out once its items are resolved. The
  inbox asks for a refresh after starting or stopping the session.
  """

  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Link

  import FirmowidWeb.Inbox.Components.Sidebar,
    only: [close_on_phone: 0, label_styles: 0, layer_label: 1, link_styles: 1]

  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Inbox.Utilities.Queue

  @cache :sidebar_status
  @empty_status %{company: 0, running?: false}

  @doc "The DOM and component id, for `send_update/3`."
  @spec id() :: String.t()
  def id, do: "app-sidebar-nav"

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, load_status(socket)}

  # A layer switch on the inbox only patches the page, so this component stays
  # mounted; it reloads the status then, as the inbox reloads its own data.
  def update(assigns, socket) do
    layer_changed? = socket.assigns[:layer] != assigns[:layer]
    socket = assign(socket, assigns)

    cond do
      !socket.assigns[:status] ->
        {:ok, socket |> assign(:cached, cached_status(socket.assigns.scope)) |> load_status()}

      layer_changed? ->
        {:ok, load_status(socket)}

      true ->
        {:ok, socket}
    end
  end

  defp load_status(socket) do
    %{scope: scope, organization: organization} = socket.assigns

    assign_async(socket, :status, fn ->
      {:ok, session} = Session.get_current(scope: scope)

      status = %{
        company: length(Queue.attention_items(scope, organization)),
        running?: session != nil
      }

      Cachex.put(@cache, cache_key(scope), status)
      {:ok, %{status: status}}
    end)
  end

  defp cached_status(scope) do
    {:ok, status} = Cachex.get(@cache, cache_key(scope))
    status || @empty_status
  end

  defp cache_key(scope), do: {scope.tenant, scope.actor.id}

  @impl true
  def render(assigns) do
    status = if assigns.status.ok?, do: assigns.status.result, else: assigns.cached

    assigns =
      assign(assigns,
        company_count: status.company,
        # Keeps the number on a badge that is fading out after its items were resolved.
        last_company_count: max(status.company, assigns.cached.company),
        running?: status.running?
      )

    ~H"""
    <nav id={@id} class="flex flex-col gap-0.5" aria-label={pgettext("sidebar", "Main")}>
      <%!--
        Side by side when expanded; collapsed, stacked as two 28 px icon buttons
        on a grey-900 tray (Figma "Sidebar / Przełącznik pionowy"). Its buttons
        stay hidden while the sidebar resizes and fade in once it has settled.
        One white pill sits under the current layer instead of each button
        painting its own. On the inbox a switch only patches the URL, so the
        pill stays in the DOM and its own transition slides it. Other pages
        render the sidebar anew, so after a live navigation the hook starts the
        pill at the layer seen last; after a full page load the server already
        painted it in place. When the pill moves, the hook dissolves the new
        layer's content in; the labels invert over the pill (difference
        blend), so they stay readable while it moves.
      --%>
      <div
        :if={@layered?}
        id="app-sidebar-layers"
        phx-hook=".LayerSwitch"
        data-layer={@layer}
        class="relative mb-3.5 grid h-8 grid-cols-2 gap-1 overflow-clip motion-safe:transition-[height,margin] motion-safe:duration-250 motion-safe:ease-out-quint md:in-data-[sidebar=collapsed]:mb-2.5 md:in-data-[sidebar=collapsed]:h-15.5 md:in-data-[sidebar=collapsed]:grid-cols-1 md:in-data-[sidebar=collapsed]:gap-0.5 md:in-data-[sidebar=collapsed]:overflow-visible md:in-data-[sidebar=collapsed]:rounded-lg md:in-data-[sidebar=collapsed]:bg-grey-900 md:in-data-[sidebar=collapsed]:p-0.5"
        role="group"
        aria-label={pgettext("sidebar", "Layer")}
      >
        <span
          data-layer-pill
          aria-hidden="true"
          class={[
            "absolute inset-y-0 left-0 w-[calc(50%-2px)] rounded-sm bg-white in-data-sidebar-moving:opacity-0 motion-safe:transition-transform motion-safe:duration-300 motion-safe:ease-out-quint md:in-data-[sidebar=collapsed]:inset-auto md:in-data-[sidebar=collapsed]:top-0.5 md:in-data-[sidebar=collapsed]:left-0.5 md:in-data-[sidebar=collapsed]:size-7 md:in-data-[sidebar=collapsed]:rounded-md",
            @layer == :me &&
              "translate-x-[calc(100%+4px)] md:in-data-[sidebar=collapsed]:translate-x-0 md:in-data-[sidebar=collapsed]:translate-y-7.5"
          ]}
        ></span>
        <.link
          :for={{layer, icon} <- [company: "building-2", me: "user"]}
          id={"app-sidebar-layer-#{layer}"}
          kind="unstyled"
          navigate={if @current_id != :inbox, do: Navigation.inbox_path(layer)}
          patch={if @current_id == :inbox, do: Navigation.inbox_path(layer)}
          phx-click={if @current_id == :inbox, do: close_on_phone()}
          aria-current={@layer == layer && "page"}
          phx-hook="TippyWhenTruncated"
          data-tippy-content={layer_label(layer)}
          data-tippy-placement="right"
          data-tippy-delay="[300, 0]"
          data-tippy-truncate-selector="[data-label]"
          class={[
            "relative flex h-8 min-w-0 items-center justify-center rounded-md font-medium transition-[color,opacity] duration-150 in-data-sidebar-moving:opacity-0 in-data-sidebar-moving:duration-0 md:in-data-[sidebar=collapsed]:size-7",
            if(@layer == layer, do: "text-white", else: "text-grey-400 hover:text-white")
          ]}
        >
          <Lucideicons.render!
            name={icon}
            class="hidden size-4.5 shrink-0 mix-blend-difference md:in-data-[sidebar=collapsed]:block"
            aria-hidden="true"
          />
          <span
            data-label
            class="truncate mix-blend-difference md:in-data-[sidebar=collapsed]:sr-only"
          >
            {layer_label(layer)}
          </span>
        </.link>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".LayerSwitch">
        // After a full page load the server painted the switch and the content
        // at their layer already; moving them in again would replay the switch.
        let painted = false

        export default {
          mounted() {
            // Clicked while another page is still loading, a patch would reach
            // the inbox being left, fail and reload it; navigate instead.
            this.el.addEventListener(
              "click",
              (e) => {
                const link = e.target.closest("[data-phx-link=patch]")
                if (link && this.liveSocket.hasPendingLink()) link.dataset.phxLink = "redirect"
              },
              true
            )
            this.sync(painted ? "navigated" : "loaded")
            painted = true
          },
          updated() { this.sync("patched") },
          sync(how) {
            const layer = this.el.dataset.layer
            let previous = null
            try {
              previous = sessionStorage.getItem("sidebar-layer")
              sessionStorage.setItem("sidebar-layer", layer)
            } catch {}
            if (how === "loaded" || !previous || previous === layer) return
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
            if (how === "navigated") this.slideFrom(previous)
            document.querySelectorAll("[data-layer-dissolve]").forEach((el) => {
              el.classList.remove("animate-dissolve")
              el.offsetWidth
              el.classList.add("animate-dissolve")
            })
          },
          // A new pill starts where the last layer had it; clearing the inline
          // style lets its transition carry it to the current layer. A patched
          // pill is already on its way, and moving it back would replay it.
          slideFrom(previous) {
            const pill = this.el.querySelector("[data-layer-pill]")
            pill.style.transition = "none"
            const collapsed =
              document.documentElement.dataset.sidebar === "collapsed" &&
              window.matchMedia("(min-width: 48rem)").matches
            const from = collapsed ? "0 30px" : "calc(100% + 4px) 0"
            pill.style.translate = previous === "me" ? from : "0 0"
            pill.offsetWidth
            pill.style.transition = ""
            pill.style.translate = ""
          }
        }
      </script>
      <.link
        id="app-sidebar-link-inbox"
        kind="unstyled"
        navigate={@inbox.path}
        aria-current={@current_id == :inbox && "page"}
        class={link_styles(@current_id == :inbox)}
        phx-hook="TippyWhenTruncated"
        data-tippy-content={@inbox.label}
        data-tippy-placement="right"
        data-tippy-delay="[300, 0]"
        data-tippy-truncate-selector="[data-label]"
      >
        <Lucideicons.render! name={@inbox.icon} class="size-4.5 shrink-0" aria-hidden="true" />
        <span data-label class={label_styles()}>{@inbox.label}</span>
        <%!-- Company items needing someone, shown in the company layer only. Collapsed, it rides the icon's corner. --%>
        <.count
          count={if @layer == :company, do: @company_count, else: 0}
          last_count={if @layer == :company, do: @last_company_count, else: 0}
          shown="ml-auto min-w-4.5 px-1"
          class={[
            "h-4.5 bg-white text-caps-sm text-black",
            collapsed_badge_styles()
          ]}
        />
      </.link>
      <.link
        :if={@layer == :me and @timetracker}
        id="app-sidebar-link-timetracker"
        kind="unstyled"
        navigate={@timetracker.path}
        aria-current={@current_id == :timetracker && "page"}
        class={link_styles(@current_id == :timetracker)}
        phx-hook="TippyWhenTruncated"
        data-tippy-content={@timetracker.label}
        data-tippy-placement="right"
        data-tippy-delay="[300, 0]"
        data-tippy-truncate-selector="[data-label]"
      >
        <Lucideicons.render! name={@timetracker.icon} class="size-4.5 shrink-0" aria-hidden="true" />
        <span data-label class={label_styles()}>{@timetracker.label}</span>
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

  attr :last_count, :integer,
    required: true,
    doc: "The number to keep on the badge while it fades out."

  attr :shown, :string,
    required: true,
    doc: "Width and spacing of the badge while it has a count."

  attr :class, :any, required: true

  # A round badge sized by the caller (18 px on the switch);
  # collapsed, it moves to the icon's corner, placed by the caller. At zero it
  # stays in the DOM and shrinks to nothing, so the text beside it slides back
  # instead of jumping; it is hidden from screen readers while empty.
  defp count(assigns) do
    ~H"""
    <span
      :if={@last_count > 0}
      aria-hidden={@count == 0 && "true"}
      class={[
        "flex shrink-0 items-center justify-center overflow-hidden rounded-full leading-none font-semibold tabular-nums motion-safe:transition-[width,margin,opacity,scale] motion-safe:duration-300 motion-safe:ease-out md:in-data-[sidebar=collapsed]:absolute",
        if(@count > 0, do: @shown, else: "w-0 scale-50 opacity-0"),
        @class
      ]}
    >
      {if @count > 0, do: @count, else: @last_count}
    </span>
    """
  end

  # Collapsed, a count rides the icon's top right corner as a 16 px white disc
  # with a black ring that cuts it out of the icon (Figma "Licznik").
  defp collapsed_badge_styles do
    "md:in-data-[sidebar=collapsed]:-top-1.5 md:in-data-[sidebar=collapsed]:-right-1.5 md:in-data-[sidebar=collapsed]:ml-0 md:in-data-[sidebar=collapsed]:size-4 md:in-data-[sidebar=collapsed]:border-2 md:in-data-[sidebar=collapsed]:border-black md:in-data-[sidebar=collapsed]:bg-white md:in-data-[sidebar=collapsed]:text-[10px] md:in-data-[sidebar=collapsed]:text-black"
  end
end
