defmodule FirmowidWeb.Settings.Components.SettingsPage do
  @moduledoc """
  Shared shell for the settings screens.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
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
    assigns =
      assign(
        assigns,
        :tabs,
        Navigation.tabs_for(%{
          current_user: assigns.current_user,
          current_org: assigns.current_org
        })
      )

    ~H"""
    <section class="container flex max-w-7xl flex-col gap-6 py-8 lg:gap-10 lg:py-10">
      <div class="flex items-center justify-between">
        <div class="flex flex-col gap-6 sm:flex-row sm:items-center sm:gap-8">
          <form class="relative" phx-submit="upload" phx-change="upload">
            <.live_file_input
              upload={@user_avatar_upload}
              class="peer sr-only"
              aria-label="Zmień zdjęcie profilowe"
            />

            <.avatar class="bg-grey-100 border-grey-100 hidden size-32 rounded-full border lg:block">
              <.avatar_image
                :if={Map.get(@current_user.avatar_blob || %{}, :url)}
                src={Map.get(@current_user.avatar_blob || %{}, :url)}
                alt={@current_user.name || @current_user.email}
              />
              <.avatar_fallback class="text-grey-700 text-2xl font-medium">
                {initial(@current_user.name || @current_user.email)}
              </.avatar_fallback>
            </.avatar>

            <.button
              as="label"
              id="settings-user-avatar-upload-tooltip"
              for={@user_avatar_upload.ref}
              type="button"
              variant="outline"
              size="small"
              aria-label="Zmień zdjęcie profilowe"
              phx-hook="Tippy"
              data-tippy-content="Zmień zdjęcie profilowe"
              data-tippy-delay="100"
              class="absolute -right-1 -bottom-1 hidden size-10 rounded-full p-0 shadow-sm lg:flex"
            >
              <Lucideicons.square_pen class="size-6!" />
            </.button>
          </form>

          <div class="flex flex-col gap-2">
            <h1 class="text-grey-900 text-2xl font-medium">
              Cześć, <span class="font-bold">{@current_user.name || "użytkowniku"}</span>!
            </h1>
            <p class="text-grey-700">{@current_user.email}</p>
          </div>
        </div>

        <div class="relative hidden lg:block">
          <form
            :if={@current_user.role == :admin && @organization_avatar_upload}
            phx-submit="upload"
            phx-change="upload"
          >
            <.live_file_input
              upload={@organization_avatar_upload}
              class="peer sr-only"
              aria-label="Zmień logo organizacji"
            />
          </form>

          <.avatar class="bg-grey-100 border-grey-100 size-32 rounded-2xl! border">
            <.avatar_image
              :if={@current_org.avatar_blob && @current_org.avatar_blob.url}
              src={@current_org.avatar_blob.url}
              alt={@current_org.name}
              class="rounded-2xl! object-contain"
            />
            <.avatar_fallback class="text-grey-700 rounded-2xl! text-center text-2xl font-medium">
              {initial(@current_org.name)}
            </.avatar_fallback>
          </.avatar>

          <.button
            :if={@current_user.role == :admin && @organization_avatar_upload}
            as="label"
            id="settings-organization-avatar-upload-tooltip"
            for={@organization_avatar_upload.ref}
            type="button"
            variant="outline"
            size="small"
            aria-label="Zmień logo organizacji"
            phx-hook="Tippy"
            data-tippy-content="Zmień logo organizacji"
            data-tippy-delay="100"
            class="absolute -right-4 -bottom-2 size-10 rounded-full p-0 shadow-sm"
          >
            <Lucideicons.square_pen class="size-6!" />
          </.button>
        </div>
      </div>

      <nav
        aria-label="Ustawienia"
        class="border-grey-200 flex flex-wrap gap-2 border-b"
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
    "inline-flex min-h-11 items-center border-b-2 border-orange-700 px-3 text-sm font-medium leading-tight text-orange-700 transition focus:outline-none focus-visible:ring-2 focus-visible:ring-orange-700"
  end

  defp tab_styles(false),
    do:
      "inline-flex min-h-11 items-center border-b-2 border-transparent px-3 text-sm font-medium leading-tight text-grey-700 transition hover:border-orange-200 hover:text-grey-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-orange-700"

  defp initial(email) do
    email
    |> to_string()
    |> String.slice(0, 1)
    |> String.upcase()
  end
end
