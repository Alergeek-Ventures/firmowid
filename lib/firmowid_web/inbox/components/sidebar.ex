defmodule FirmowidWeb.Inbox.Components.Sidebar do
  @moduledoc """
  The app's sidebar behind the `inbox` flag: the inbox, then the places of one
  layer listed flat. The switch at the top moves between the company layer and
  the member's own layer, landing in that layer's inbox.

  On desktop it collapses to icons; the state lives on `<html data-sidebar>`
  (restored from local storage in the root layout), so it survives navigation
  without a server round trip. On phones it opens over the page from a top bar.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Infrastructure.Layouts

  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :organizations, :list, required: true
  attr :current_uri, URI, required: true
  attr :analysis_enabled, :boolean, required: true

  @doc "Renders the sidebar and, on phones, the top bar that opens it."
  def sidebar(assigns) do
    destinations = Navigation.for_role(assigns.current_user.member.role, assigns.analysis_enabled)
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
    <.navbar class="sticky top-0 z-40 flex h-navbar items-center justify-between md:hidden">
      <.navbar_logo navigate={@inbox.path} />
      <.button
        variant="unstyled"
        type="button"
        class="p-1"
        phx-click={JS.toggle_class("max-md:hidden", to: "#app-sidebar")}
        aria-label={pgettext("main navigation", "Navigation menu")}
      >
        <.icon name="hero-bars-3" class="size-6" />
      </.button>
    </.navbar>
    <aside
      id="app-sidebar"
      class="fixed inset-y-0 left-0 z-50 flex w-64 flex-col gap-6 overflow-y-auto bg-black px-3 py-5 text-sm text-white [--focus-ring:var(--color-white)] max-md:hidden max-md:w-full md:in-data-[sidebar=collapsed]:w-16 md:in-data-[sidebar=collapsed]:px-2"
    >
      <div class="flex items-center justify-between gap-2 px-2 md:in-data-[sidebar=collapsed]:justify-center md:in-data-[sidebar=collapsed]:px-0">
        <div class="flex min-w-0 flex-col gap-0.5 md:in-data-[sidebar=collapsed]:hidden">
          <.navbar_logo navigate={@inbox.path} />
          <span class="truncate text-xs text-white/50">{@current_org.name}</span>
        </div>
        <.button
          variant="unstyled"
          id="app-sidebar-collapse"
          type="button"
          phx-hook=".SidebarCollapse"
          class="rounded-md p-1.5 text-white/60 transition-colors hover:bg-grey-700/50 hover:text-white max-md:hidden"
          aria-label={gettext("Collapse or expand the menu")}
          title={gettext("Collapse or expand the menu")}
        >
          <Lucideicons.panel_left class="size-4" aria-hidden="true" />
        </.button>
        <.button
          variant="unstyled"
          type="button"
          phx-click={JS.toggle_class("max-md:hidden", to: "#app-sidebar")}
          class="rounded-md p-1.5 text-white/60 hover:text-white md:hidden"
          aria-label={gettext("Close the menu")}
        >
          <Lucideicons.x class="size-5" aria-hidden="true" />
        </.button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarCollapse">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
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
      <nav class="flex flex-col gap-0.5" aria-label={pgettext("sidebar", "Main")}>
        <.layer_switch :if={@layered?} layer={@layer} />
        <.sidebar_link destination={@inbox} active={@current_id == :inbox} />
        <.sidebar_link
          :if={@layer == :me}
          destination={@timetracker}
          active={@current_id == :timetracker}
        />
      </nav>
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

  attr :layer, :atom, required: true

  defp layer_switch(assigns) do
    ~H"""
    <div
      class="mb-2 grid grid-cols-2 rounded-full bg-grey-800 p-1 md:in-data-[sidebar=collapsed]:grid-cols-1 md:in-data-[sidebar=collapsed]:gap-1 md:in-data-[sidebar=collapsed]:rounded-md"
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
          "flex items-center justify-center gap-2 rounded-full py-1.5 font-medium transition-colors md:in-data-[sidebar=collapsed]:rounded-md",
          if(@layer == layer, do: "bg-white text-black", else: "text-white/60 hover:text-white")
        ]}
      >
        <Lucideicons.render!
          name={icon}
          class="hidden size-4 md:in-data-[sidebar=collapsed]:block"
          aria-hidden="true"
        />
        <span class="md:in-data-[sidebar=collapsed]:sr-only">{layer_label(layer)}</span>
      </.link>
    </div>
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
