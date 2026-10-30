defmodule FirmowidWeb.Settings.Components.SettingsPage do
  @moduledoc """
  Shared shell for the settings screens.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Settings.Utilities.Navigation

  @doc """
  Renders the shared settings header and route navigation.
  """
  @spec settings_page(map()) :: Phoenix.LiveView.Rendered.t()
  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :current_tab, :atom, required: true
  attr :user_avatar_upload, :any, required: true
  attr :organization_avatar_upload, :any, default: nil
  slot :inner_block, required: true

  def settings_page(assigns) do
    [greeting_before, greeting_after] =
      "Hi, %{name}!"
      |> gettext(name: "__NAME__")
      |> String.split("__NAME__", parts: 2)

    assigns =
      assigns
      |> assign(
        :tabs,
        Navigation.tabs_for(%{
          current_user: assigns.current_user,
          current_org: assigns.current_org
        })
      )
      |> assign(greeting_before: greeting_before, greeting_after: greeting_after)

    ~H"""
    <section class="container flex max-w-7xl flex-col gap-6 py-8 lg:gap-10 lg:py-10">
      <div class="flex items-center justify-between">
        <div class="flex flex-col gap-6 sm:flex-row sm:items-center sm:gap-8">
          <form class="relative" phx-submit="upload" phx-change="upload">
            <.live_file_input
              upload={@user_avatar_upload}
              class="peer sr-only"
              aria-label={gettext("Change profile picture")}
            />

            <.avatar class="hidden size-32 rounded-full border border-grey-100 bg-grey-100 lg:block">
              <.avatar_image
                :if={Map.get(@current_user.member.avatar_blob || %{}, :url)}
                src={Map.get(@current_user.member.avatar_blob || %{}, :url)}
                alt={@current_user.member.name || @current_user.email}
              />
              <.avatar_fallback class="text-2xl font-medium text-grey-700">
                {initial(@current_user.member.name || @current_user.email)}
              </.avatar_fallback>
            </.avatar>

            <.button
              as="label"
              id="settings-user-avatar-upload-tooltip"
              for={@user_avatar_upload.ref}
              type="button"
              variant="outline"
              size="small"
              aria-label={gettext("Change profile picture")}
              phx-hook="Tippy"
              data-tippy-content={gettext("Change profile picture")}
              data-tippy-delay="100"
              class="absolute -right-1 -bottom-1 size-10 rounded-full bg-white p-0 shadow-sm max-lg:hidden"
            >
              <Lucideicons.square_pen class="size-6!" />
            </.button>
          </form>

          <div class="flex flex-col gap-2">
            <h1 class="text-2xl font-medium text-grey-900">
              {@greeting_before}<span class="font-bold">{@current_user.member.name || pgettext("greeting fallback", "user")}</span>{@greeting_after}
            </h1>
            <p class="text-grey-700">{@current_user.email}</p>
          </div>
        </div>

        <div class="relative hidden lg:block">
          <form
            :if={@current_user.member.role == :admin && @organization_avatar_upload}
            phx-submit="upload"
            phx-change="upload"
          >
            <.live_file_input
              upload={@organization_avatar_upload}
              class="peer sr-only"
              aria-label={gettext("Change organization logo")}
            />
          </form>

          <.avatar class="size-32 rounded-2xl! border border-grey-100 bg-grey-100">
            <.avatar_image
              :if={@current_org.avatar_blob && @current_org.avatar_blob.url}
              src={@current_org.avatar_blob.url}
              alt={@current_org.name}
              class="rounded-2xl! object-contain"
            />
            <.avatar_fallback class="rounded-2xl! text-center text-2xl font-medium text-grey-700">
              {initial(@current_org.name)}
            </.avatar_fallback>
          </.avatar>

          <.button
            :if={@current_user.member.role == :admin && @organization_avatar_upload}
            as="label"
            id="settings-organization-avatar-upload-tooltip"
            for={@organization_avatar_upload.ref}
            type="button"
            variant="outline"
            size="small"
            aria-label={gettext("Change organization logo")}
            phx-hook="Tippy"
            data-tippy-content={gettext("Change organization logo")}
            data-tippy-delay="100"
            class="absolute -right-4 -bottom-2 size-10 rounded-full bg-white p-0 shadow-sm"
          >
            <Lucideicons.square_pen class="size-6!" />
          </.button>
        </div>
      </div>

      <nav
        aria-label={pgettext("settings navigation", "Settings")}
        class="flex flex-wrap gap-2 border-b border-grey-200"
      >
        <%= for tab <- @tabs do %>
          <.link
            kind="unstyled"
            patch={tab.path}
            aria-current={if active_tab?(tab.id, @current_tab), do: "page"}
            class={tab_styles(active_tab?(tab.id, @current_tab))}
          >
            {tab.label}
          </.link>
        <% end %>
      </nav>

      {render_slot(@inner_block)}
    </section>
    """
  end

  defp active_tab?(tab_id, current_tab), do: tab_id == current_tab

  defp tab_styles(true) do
    "inline-flex min-h-11 items-center border-b-2 border-rust-700 px-3 text-sm font-medium leading-tight text-rust-700 transition focus:outline-none focus-visible:ring-2 focus-visible:ring-rust-700"
  end

  defp tab_styles(false),
    do:
      "inline-flex min-h-11 items-center border-b-2 border-transparent px-3 text-sm font-medium leading-tight text-grey-700 transition hover:border-rust-200 hover:text-grey-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-rust-700"

  defp initial(email) do
    email
    |> to_string()
    |> String.slice(0, 1)
    |> String.upcase()
  end
end
