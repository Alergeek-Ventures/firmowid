defmodule FirmowidWeb.Inbox.Components.Sidebar do
  @moduledoc """
  The app's sidebar: the inbox, then the places of one layer listed flat. The
  switch at the top moves between the company layer and the member's own layer,
  landing in that layer's inbox.

  The panel button right of the wordmark collapses it to icons on desktop; the
  state lives on `<html data-sidebar>` (restored from local storage in the root
  layout), so it survives navigation without a server round trip. On phones the
  hamburger in the top bar slides it in over the page and the same button,
  showing a close icon, slides it out.

  Collapsing keeps every icon exactly where it was: the sidebar narrows to the
  icon column while the labels fade, and nothing changes height, so only the
  width animates.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.DesignSystem.Components.FigmaIcon
  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Infrastructure.Layouts

  # Off-screen and hidden from focus on phones until the top bar slides it in.
  @closed_on_phone "max-md:-translate-x-full max-md:invisible"

  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :organizations, :list, required: true
  attr :current_uri, URI, required: true
  attr :analysis_enabled, :boolean, required: true
  attr :delegations_enabled, :boolean, required: true
  attr :taxes_enabled, :boolean, required: true
  attr :scope, Firmowid.Scope, required: true

  @doc "Renders the sidebar and, on phones, the top bar that opens it."
  def sidebar(assigns) do
    destinations =
      Navigation.for_role(
        assigns.current_user.member.role,
        assigns.analysis_enabled,
        assigns.current_org.owner_id == assigns.current_user.id,
        assigns.delegations_enabled,
        assigns.current_org.bills_hourly
      )

    current = Navigation.current(destinations, assigns.current_uri)
    layered? = Navigation.in_layer(destinations, :company) != []
    layer = layer(layered?, current, assigns.current_uri)
    [inbox | main] = Navigation.in_layer(destinations, :main)

    assigns =
      assign(assigns,
        destinations: destinations,
        current_id: current && current.id,
        layered?: layered?,
        layer: layer,
        inbox: %{inbox | path: Navigation.inbox_path(layer)},
        timetracker: List.first(main),
        closed_on_phone: @closed_on_phone
      )

    ~H"""
    <%!-- Same insets as the sidebar head, so the wordmark and button stay put as it slides in.
    Fixed rather than sticky, and its black runs on above the screen's top edge, where Safari
    shows the page through its address bar: there the bar shows black instead of the page
    scrolling under it. The layout keeps the bar's height free (see the app layout). --%>
    <.navbar class="fixed inset-x-0 top-0 z-40 flex h-14 items-center gap-3 pr-1! pl-4! before:absolute before:inset-x-0 before:bottom-full before:h-screen before:bg-black md:hidden">
      <span class="font-logo text-[22px]/7 font-extrabold text-white">
        Firmowid
      </span>
      <%!-- Figma "Górny pasek": the sidebar's own panel icon, white, 24 px in a 48 px touch target. --%>
      <.panel_button
        class="m-0! ml-auto! size-12!"
        phx-click={JS.toggle_class(@closed_on_phone, to: "#app-sidebar")}
        label={pgettext("main navigation", "Navigation menu")}
      >
        <.figma_icon name="zwin_panel" class="size-6 text-white" />
      </.panel_button>
    </.navbar>
    <aside
      id="app-sidebar"
      class={[
        "fixed inset-y-0 left-0 z-50 flex w-64 flex-col gap-6 overflow-x-hidden overflow-y-auto bg-black px-3 py-4 text-sm text-white [--focus-ring:var(--color-white)] max-md:w-full max-md:pt-3.5 max-md:ease-out-quint motion-safe:max-md:transition-[translate,visibility] motion-safe:max-md:duration-300 md:ease-out-quint md:in-data-[sidebar=collapsed]:w-14 motion-safe:md:transition-[width] motion-safe:md:duration-250",
        @closed_on_phone
      ]}
    >
      <div class="flex items-center gap-1.5 md:in-data-[sidebar=collapsed]:gap-0">
        <%!-- The wordmark lines up with the icons below and fades with the labels when collapsed. --%>
        <span class={[
          "pl-1 font-logo text-[22px]/7 font-extrabold text-white md:in-data-[sidebar=collapsed]:pl-0",
          label_styles()
        ]}>
          Firmowid
        </span>
        <%!-- Collapsed, the wordmark gives up its width, so the button lands on the icon column. --%>
        <.panel_button
          id="app-sidebar-collapse"
          phx-hook=".SidebarCollapse"
          phx-click={close_on_phone()}
          label={gettext("Collapse or expand the menu")}
          class="max-md:-my-2.5 max-md:-mr-2 max-md:size-12"
        >
          <%!-- Collapses on desktop; on phones it closes the menu the hamburger opened. --%>
          <.figma_icon
            name="zwin_panel"
            class="size-5.5 max-md:hidden md:in-data-[sidebar=collapsed]:size-4.5"
          />
          <Lucideicons.x class="size-5.5 md:hidden" aria-hidden="true" />
        </.panel_button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarCollapse">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              if (!window.matchMedia("(min-width: 48rem)").matches) return;
              const root = document.documentElement;
              const collapsed = root.dataset.sidebar !== "collapsed";
              if (collapsed) root.dataset.sidebar = "collapsed";
              else delete root.dataset.sidebar;
              // Marks the first, fastest part of the width animation, for parts
              // that hide while it lasts; they come back with the labels (delay-100).
              root.dataset.sidebarMoving = "";
              clearTimeout(this.moving);
              this.moving = setTimeout(() => delete root.dataset.sidebarMoving, 100);
              try {
                localStorage.setItem("sidebar", collapsed ? "collapsed" : "expanded");
              } catch {}
            });
          }
        }
      </script>
      <.live_component
        module={SidebarNav}
        id={SidebarNav.id()}
        scope={@scope}
        organization={@current_org}
        taxes_enabled={@taxes_enabled}
        layer={@layer}
        layered?={@layered?}
        current_id={@current_id}
        inbox={@inbox}
        timetracker={@timetracker}
      />
      <%!-- Dissolves in when the layer changes (see SidebarNav's LayerSwitch hook). --%>
      <nav
        data-layer-dissolve
        class="mt-2 flex flex-col gap-0.5 motion-safe:transition-[margin] motion-safe:duration-250 motion-safe:ease-out-quint md:in-data-[sidebar=collapsed]:mt-0.5"
        aria-label={layer_label(@layer)}
      >
        <%!--
          Collapsed, the header folds away while the taller vertical switch takes
          its room, so the links below land where they were (Figma "Zwinięty").
        --%>
        <h2 class="h-[19px] overflow-clip px-2 pb-1.5 text-caps-sm/[13px] font-normal whitespace-nowrap text-grey-500 uppercase motion-safe:transition-[height,padding] motion-safe:duration-250 motion-safe:ease-out-quint md:in-data-[sidebar=collapsed]:h-0 md:in-data-[sidebar=collapsed]:pb-0">
          <span class={label_styles()}>{layer_label(@layer)}</span>
        </h2>
        <.sidebar_link
          :for={destination <- Navigation.in_layer(@destinations, @layer)}
          destination={destination}
          active={@current_id == destination.id}
        />
      </nav>
      <div class="mt-auto flex flex-col gap-0.5 border-t border-grey-800 pt-11 motion-safe:transition-[padding] motion-safe:duration-250 motion-safe:ease-out-quint md:in-data-[sidebar=collapsed]:pt-3">
        <.button
          id="app-sidebar-support"
          variant="unstyled"
          type="button"
          phx-click={show_modal("support-modal")}
          class={link_styles(false)}
          phx-hook="TippyWhenTruncated"
          data-tippy-content={pgettext("sidebar", "Feedback")}
          data-tippy-placement="right"
          data-tippy-delay="[300, 0]"
          data-tippy-truncate-selector="[data-label]"
        >
          <.figma_icon name="feedback" class="size-4.5" />
          <span data-label class={label_styles()}>{pgettext("sidebar", "Feedback")}</span>
        </.button>
        <.button
          variant="unstyled"
          type="button"
          phx-click={
            JS.toggle(
              to: "#app-sidebar-account",
              display: "flex",
              out: account_menu_out(),
              time: 100
            )
            |> JS.toggle_class("bg-grey-900 text-white")
          }
          phx-click-away={
            JS.hide(to: "#app-sidebar-account", transition: account_menu_out(), time: 100)
            |> JS.remove_class("bg-grey-900 text-white")
          }
          id="app-sidebar-account-button"
          class={link_styles(false)}
          phx-hook="TippyWhenTruncated"
          data-tippy-content={@current_user.email}
          data-tippy-placement="right"
          data-tippy-delay="[300, 0]"
          data-tippy-truncate-selector="[data-label]"
        >
          <.figma_icon name="user_circle" class="size-4.5" />
          <span data-label class={label_styles()}>{@current_user.email}</span>
        </.button>
        <div
          id="app-sidebar-account"
          style="display: none"
          class="fixed bottom-14 left-3 z-50 w-58 origin-bottom flex-col rounded-[8px] bg-grey-950 p-2 shadow-small ring-1 ring-grey-800 transition-[opacity,scale] duration-150 ease-out ring-inset motion-reduce:transition-none max-md:inset-x-3 max-md:w-auto starting:scale-95 starting:opacity-0"
        >
          <Layouts.account_menu
            current_user={@current_user}
            current_org={@current_org}
            organizations={@organizations}
          />
        </div>
      </div>
    </aside>
    """
  end

  # The account menu shrinks and fades out in 100 ms; it opens through
  # `starting:` on the panel itself (DESIGN.md, Motion: Dropdown).
  defp account_menu_out do
    {"transition-[opacity,scale] duration-100! ease-in! motion-reduce:transition-none", "scale-100 opacity-100",
     "scale-95 opacity-0"}
  end

  # The inbox carries its layer in the URL; elsewhere the page decides, and
  # pages outside the list belong to the company for members who have one.
  defp layer(false, _current, _uri), do: :me

  defp layer(true, %{id: :inbox}, uri) do
    Navigation.parse_layer(URI.decode_query(uri.query || "")["warstwa"])
  end

  defp layer(true, %{layer: layer}, _uri) when layer in [:company, :me], do: layer
  defp layer(true, %{id: :timetracker}, _uri), do: :me
  defp layer(true, nil, _uri), do: :company

  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  # The icon button right of the wordmark that opens, closes or collapses the sidebar.
  # Its 32 px hit area overhangs the 28 px head row, so the 22 px icon sits on the
  # row's right edge as in Figma; collapsed, it starts at the top inset instead
  # and only overhangs below, so the switch keeps its place.
  defp panel_button(assigns) do
    ~H"""
    <.button
      variant="unstyled"
      type="button"
      class={[
        "-my-0.5 -mr-1.25 flex size-8 shrink-0 items-center justify-center rounded-[2px] text-white transition-colors duration-100 hover:bg-white/10 active:bg-white/15 motion-reduce:transition-none md:in-data-[sidebar=collapsed]:mt-0 md:in-data-[sidebar=collapsed]:mr-0 md:in-data-[sidebar=collapsed]:-mb-1",
        @class
      ]}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.button>
    """
  end

  @doc "Name of a sidebar layer."
  @spec layer_label(:company | :me) :: String.t()
  def layer_label(:company), do: pgettext("sidebar layer", "Company")
  def layer_label(:me), do: pgettext("sidebar layer", "You")

  attr :destination, :map, required: true
  attr :active, :boolean, required: true

  defp sidebar_link(assigns) do
    ~H"""
    <%!-- The tooltip shows only while the label is cut off, i.e. when collapsed. --%>
    <.link
      id={"app-sidebar-link-#{@destination.id}"}
      kind="unstyled"
      navigate={@destination.path}
      aria-current={@active && "page"}
      class={link_styles(@active)}
      phx-hook="TippyWhenTruncated"
      data-tippy-content={@destination.label}
      data-tippy-placement="right"
      data-tippy-delay="[300, 0]"
      data-tippy-truncate-selector="[data-label]"
    >
      <.figma_icon :if={FigmaIcon.icon?(@destination.icon)} name={@destination.icon} class="size-4.5" />
      <Lucideicons.render!
        :if={!FigmaIcon.icon?(@destination.icon)}
        name={@destination.icon}
        class="size-4.5 shrink-0"
        aria-hidden="true"
      />
      <%!-- The badge sits inside the label, so it follows the name and fades with it when collapsed. --%>
      <span data-label class={label_styles()}>{@destination.label}
      <span
        :if={@destination[:beta?]}
        id={"app-sidebar-beta-#{@destination.id}"}
        class="ml-1.5 inline-block rounded bg-white/20 px-1.5 align-top text-xs/5"
        phx-hook="Tippy"
        data-tippy-content={
          gettext(
            "This feature is still in progress! Your feedback will help us make it even better."
          )
        }
      >BETA</span></span>
    </.link>
    """
  end

  @doc """
  Slides the sidebar out on phones; links that only patch the page call it,
  since the sidebar would otherwise stay open over it.
  """
  @spec close_on_phone() :: JS.t()
  def close_on_phone, do: JS.add_class(@closed_on_phone, to: "#app-sidebar")

  @doc """
  A sidebar row as in the Figma "Sidebar / Link": 32 px tall, an 18 px icon 8 px
  in, grey-300 text, and the current page on a grey-900 fill. Collapsed ("Sidebar
  / Link ikona"), the inset shrinks to 7 px so the icon centers in a 32 px square
  and the current page sits on a grey-800 fill with 4 px corners; it is relative
  for the corner badges.
  """
  @spec link_styles(boolean()) :: list(String.t())
  def link_styles(active?) do
    [
      "relative flex w-full items-center gap-3 px-2 py-1.5 text-left leading-5 transition-colors duration-100 motion-reduce:transition-none md:in-data-[sidebar=collapsed]:px-1.75",
      if(active?,
        do:
          "rounded-[2px] bg-grey-900 text-white md:in-data-[sidebar=collapsed]:rounded-sm md:in-data-[sidebar=collapsed]:bg-grey-800",
        else:
          "rounded-[2px] text-grey-300 hover:bg-grey-900/60 hover:text-white md:in-data-[sidebar=collapsed]:rounded-sm"
      )
    ]
  end

  @doc """
  A link label that fades out as the sidebar collapses (cut off by the edge, no
  ellipsis) and fades back in once there is room again; it stays readable to
  screen readers either way.
  """
  @spec label_styles() :: String.t()
  def label_styles do
    "min-w-0 flex-1 truncate transition-opacity duration-150 delay-100 md:in-data-[sidebar=collapsed]:text-clip md:in-data-[sidebar=collapsed]:opacity-0 md:in-data-[sidebar=collapsed]:duration-100 md:in-data-[sidebar=collapsed]:delay-0"
  end
end
