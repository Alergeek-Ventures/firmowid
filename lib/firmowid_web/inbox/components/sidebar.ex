defmodule FirmowidWeb.Inbox.Components.Sidebar do
  @moduledoc """
  The app's sidebar behind the `inbox` flag: the inbox, then the places of one
  layer listed flat. The switch at the top moves between the company layer and
  the member's own layer, landing in that layer's inbox.

  The Firmowid head at the top collapses it to icons on desktop; the state
  lives on `<html data-sidebar>` (restored from local storage in the root
  layout), so it survives navigation without a server round trip. On phones the
  head in the top bar opens it over the page and the one in the sidebar closes it.
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
  attr :scope, Firmowid.Scope, required: true

  @doc "Renders the sidebar and, on phones, the top bar that opens it."
  def sidebar(assigns) do
    destinations =
      Navigation.for_role(
        assigns.current_user.member.role,
        assigns.analysis_enabled,
        assigns.current_org.owner_id == assigns.current_user.id
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
        timetracker: timetracker
      )

    ~H"""
    <.navbar class="sticky top-0 z-40 flex h-navbar items-center gap-3 md:hidden">
      <.head_button
        phx-click={JS.toggle_class("max-md:hidden", to: "#app-sidebar")}
        label={pgettext("main navigation", "Navigation menu")}
      />
      <span class="truncate text-sm text-white/70">{@current_org.name}</span>
    </.navbar>
    <aside
      id="app-sidebar"
      class="fixed inset-y-0 left-0 z-50 flex w-64 flex-col gap-6 overflow-y-auto bg-black px-3 py-5 text-sm text-white [--focus-ring:var(--color-white)] max-md:hidden max-md:w-full md:in-data-[sidebar=collapsed]:w-16 md:in-data-[sidebar=collapsed]:px-2"
    >
      <div class="flex items-center gap-3 px-1 md:in-data-[sidebar=collapsed]:justify-center md:in-data-[sidebar=collapsed]:px-0">
        <.head_button
          id="app-sidebar-collapse"
          phx-hook=".SidebarCollapse"
          phx-click={JS.add_class("max-md:hidden", to: "#app-sidebar")}
          label={gettext("Collapse or expand the menu")}
        />
        <span class="truncate text-xs text-white/50 md:in-data-[sidebar=collapsed]:hidden">
          {@current_org.name}
        </span>
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
        <h2 class="px-2 pb-1 text-caps-sm tracking-wide text-white/40 uppercase md:in-data-[sidebar=collapsed]:sr-only">
          {layer_label(@layer)}
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
          <.icon name="hero-chat-bubble-left-ellipsis" class="size-4 shrink-0" />
          <span class="truncate md:in-data-[sidebar=collapsed]:sr-only">{gettext("Feedback")}</span>
        </.button>
        <.button
          variant="unstyled"
          type="button"
          phx-click={JS.toggle(to: "#app-sidebar-account", display: "flex")}
          phx-click-away={JS.hide(to: "#app-sidebar-account")}
          class={link_styles(false)}
          title={@current_user.email}
        >
          <.icon name="hero-user" class="size-4 shrink-0" />
          <span class="truncate md:in-data-[sidebar=collapsed]:sr-only">{@current_user.email}</span>
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
  defp head_button(assigns) do
    ~H"""
    <.button
      variant="unstyled"
      type="button"
      class="shrink-0 rounded-md transition-opacity hover:opacity-80"
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <img src={~p"/images/favicon.png"} alt="" class="size-8 rounded-md" />
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
      <span class="truncate md:in-data-[sidebar=collapsed]:sr-only">{@destination.label}</span>
    </.link>
    """
  end

  defp link_styles(active?) do
    [
      "flex w-full items-center gap-3 rounded-md px-2 py-1.5 text-left transition-colors hover:bg-grey-700/50 md:in-data-[sidebar=collapsed]:justify-center",
      if(active?, do: "bg-grey-700/70 text-white", else: "text-white/70")
    ]
  end
end
