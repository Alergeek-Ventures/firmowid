defmodule FirmowidWeb.Inbox.Components.Sidebar do
  @moduledoc """
  The app's sidebar behind the `inbox` flag: the inbox, then the places of one
  layer listed flat. The switch at the top moves between the company layer and
  the member's own layer, landing in that layer's inbox.

  The Firmowid head at the top collapses it to icons on desktop; the state
  lives on `<html data-sidebar>` (restored from local storage in the root
  layout), so it survives navigation without a server round trip. On phones the
  head in the top bar slides it in over the page and the one in the sidebar
  slides it out.

  Collapsing keeps every icon exactly where it was: the sidebar narrows to the
  icon column while the labels fade, and nothing changes height, so only the
  width animates.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Infrastructure.Layouts

  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :organizations, :list, required: true
  attr :current_uri, URI, required: true
  attr :analysis_enabled, :boolean, required: true
  attr :delegations_enabled, :boolean, required: true
  attr :scope, Firmowid.Scope, required: true

  @doc "Renders the sidebar and, on phones, the top bar that opens it."
  def sidebar(assigns) do
    destinations =
      Navigation.for_role(
        assigns.current_user.member.role,
        assigns.analysis_enabled,
        assigns.current_org.owner_id == assigns.current_user.id,
        assigns.delegations_enabled
      )

    current = Navigation.current(destinations, assigns.current_uri)
    layered? = Navigation.in_layer(destinations, :company) != []
    layer = layer(layered?, current, assigns.current_uri)
    [inbox, timetracker] = Navigation.in_layer(destinations, :main)

    assigns =
      assign(assigns,
        destinations: destinations,
        current_id: current && current.id,
        layered?: layered?,
        layer: layer,
        inbox: %{inbox | path: Navigation.inbox_path(layer)},
        timetracker: timetracker,
        # Off-screen and hidden from focus on phones until the top bar slides it in.
        closed_on_phone: "max-md:-translate-x-full max-md:invisible"
      )

    ~H"""
    <.navbar class="sticky top-0 z-40 flex h-navbar items-center gap-3 md:hidden">
      <.head_button
        phx-click={JS.toggle_class(@closed_on_phone, to: "#app-sidebar")}
        label={pgettext("main navigation", "Navigation menu")}
      />
    </.navbar>
    <aside
      id="app-sidebar"
      class={[
        "fixed inset-y-0 left-0 z-50 flex w-64 flex-col gap-6 overflow-x-hidden overflow-y-auto bg-black px-3 py-5 text-sm text-white [--focus-ring:var(--color-white)] max-md:w-full max-md:ease-out-quint motion-safe:max-md:transition-[translate,visibility] motion-safe:max-md:duration-300 md:ease-out-quint md:in-data-[sidebar=collapsed]:w-14 motion-safe:md:transition-[width] motion-safe:md:duration-250",
        @closed_on_phone
      ]}
    >
      <div class="flex items-center">
        <.head_button
          id="app-sidebar-collapse"
          phx-hook=".SidebarCollapse"
          phx-click={JS.add_class(@closed_on_phone, to: "#app-sidebar")}
          label={gettext("Collapse or expand the menu")}
        />
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
              // Marks the width animation, for parts that wait until it ends.
              root.dataset.sidebarMoving = "";
              clearTimeout(this.moving);
              this.moving = setTimeout(() => delete root.dataset.sidebarMoving, 250);
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
        layer={@layer}
        layered?={@layered?}
        current_id={@current_id}
        inbox={@inbox}
        timetracker={@timetracker}
      />
      <nav class="flex flex-col gap-0.5" aria-label={layer_label(@layer)}>
        <%!-- Keeps its height when collapsed, so the links below never move. --%>
        <h2 class="overflow-clip px-2 pb-1 text-caps-sm tracking-wide whitespace-nowrap text-white/40 uppercase">
          <span class={label_styles()}>{layer_label(@layer)}</span>
        </h2>
        <.sidebar_link
          :for={destination <- Navigation.in_layer(@destinations, @layer)}
          destination={destination}
          active={@current_id == destination.id}
        />
      </nav>
      <div class="mt-auto flex flex-col gap-0.5 border-t border-grey-700/50 pt-4">
        <.button
          variant="unstyled"
          type="button"
          phx-click={show_modal("feedback-modal")}
          class={link_styles(false)}
          title={gettext("Feedback")}
        >
          <Lucideicons.message_square_text class="size-4 shrink-0" aria-hidden="true" />
          <span class={label_styles()}>{gettext("Feedback")}</span>
        </.button>
        <.button
          variant="unstyled"
          type="button"
          phx-click={JS.toggle(to: "#app-sidebar-account", display: "flex")}
          phx-click-away={JS.hide(to: "#app-sidebar-account")}
          class={link_styles(false)}
          title={@current_user.email}
        >
          <Lucideicons.circle_user class="size-4 shrink-0" aria-hidden="true" />
          <span class={label_styles()}>{@current_user.email}</span>
        </.button>
        <div
          id="app-sidebar-account"
          style="display: none"
          class="fixed bottom-16 left-3 z-50 w-60 flex-col gap-2 rounded-md bg-black p-3 font-semibold shadow-lg ring-1 ring-grey-700 max-md:inset-x-3 max-md:w-auto"
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
  attr :rest, :global

  # The Firmowid head as the button that opens, closes or collapses the sidebar.
  # A vector trace of the favicon drawing, so it stays sharp at any pixel density.
  defp head_button(assigns) do
    ~H"""
    <.button
      variant="unstyled"
      type="button"
      class="flex size-8 shrink-0 items-center justify-center rounded-md transition-colors hover:bg-white/10 active:bg-white/15"
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <img src={~p"/images/logo-head.svg"} alt="" class="size-8" />
    </.button>
    """
  end

  defp layer_label(:company), do: pgettext("sidebar layer", "Company")
  defp layer_label(:me), do: pgettext("sidebar layer", "You")

  attr :destination, :map, required: true
  attr :active, :boolean, required: true

  defp sidebar_link(assigns) do
    ~H"""
    <.link
      kind="unstyled"
      navigate={@destination.path}
      aria-current={@active && "page"}
      title={@destination.label}
      class={link_styles(@active)}
    >
      <Lucideicons.render! name={@destination.icon} class="size-4 shrink-0" aria-hidden="true" />
      <span class={label_styles()}>{@destination.label}</span>
    </.link>
    """
  end

  defp link_styles(active?) do
    [
      "flex w-full items-center gap-3 rounded-md px-2 py-1.5 text-left transition-colors hover:bg-grey-700/50",
      if(active?, do: "bg-grey-700/70 text-white", else: "text-white/70")
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
