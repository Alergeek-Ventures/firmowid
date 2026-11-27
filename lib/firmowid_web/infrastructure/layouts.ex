defmodule FirmowidWeb.Infrastructure.Layouts do
  @moduledoc """
  HTML layout helpers and embedded layout templates for the web UI.

  See the `layouts` directory for available templates.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use FirmowidWeb, :controller` and
  `use FirmowidWeb, :live_view`.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Infrastructure.Flags
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Landing.Utilities.GuideStructuredData

  embed_templates "layouts/*"

  attr :current_user, :map, default: nil

  @doc """
  Bottom banner shown while a superuser uses the application as another account
  (see `Firmowid.Core.impersonator_id/1`), with the way back to their own.
  """
  def impersonation_banner(assigns) do
    ~H"""
    <div
      :if={impersonating?(@current_user)}
      id="impersonation-banner"
      class="pointer-events-none fixed inset-x-0 bottom-0 z-100 p-4"
    >
      <div class="pointer-events-auto mx-auto flex w-fit max-w-full flex-wrap items-center gap-x-4 gap-y-2 rounded-xl bg-rust-700 px-5 py-3 text-sm text-white shadow-2xl">
        <Lucideicons.venetian_mask class="size-5 shrink-0" aria-hidden="true" />
        <p>
          {gettext("You are using the app as %{email}. Analytics are not recorded.",
            email: @current_user.email
          )}
        </p>
        <.form for={%{}} action={~p"/admin/impersonacja"} method="delete">
          <.button
            type="submit"
            variant="tertiary"
            size="small"
            class="bg-white text-black hover:bg-white/90 active:bg-white/80"
          >
            {gettext("Return to your account")}
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :organizations, :list, required: true

  @doc """
  The sidebar's account menu (Figma "Menu konta"): who is logged in, the
  organization switcher, settings and logging out.
  """
  def account_menu(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 p-2">
      <span
        class="flex size-8 shrink-0 items-center justify-center rounded-full bg-grey-800 text-[13px] font-semibold text-white uppercase"
        aria-hidden="true"
      >
        {@current_user.email |> to_string() |> String.first()}
      </span>
      <div class="flex min-w-0 flex-col gap-0.5">
        <span class="text-caps-sm/[14px] text-grey-500">{pgettext("avatar menu", "Logged in as")}</span>
        <span class="truncate text-[13px]/[17px] font-medium text-white lowercase">
          {@current_user.email}
        </span>
      </div>
    </div>
    <.account_menu_separator />
    <div id="organization-switcher" class="flex flex-col gap-0.5">
      <div class="truncate px-2 pt-1 pb-1.5 text-caps-sm/[14px] font-semibold tracking-[0.04em] text-grey-500 uppercase">
        {pgettext("avatar menu", "Organizations")}
      </div>
      <div
        class={["bg-grey-900 font-medium text-white", account_menu_org_styles()]}
        title={@current_org.display_name}
        aria-current="true"
      >
        <.org_avatar name={@current_org.display_name} class="bg-white text-black" />
        <span class="min-w-0 flex-1 truncate">{@current_org.display_name}</span>
        <.figma_icon name="check" class="size-4" />
      </div>
      <%= for organization <- @organizations, organization.id != @current_org.id do %>
        <%= if Firmowid.Core.usable_organization?(@current_user, organization) do %>
          <.form
            for={%{}}
            id={"switch-organization-#{organization.id}"}
            action={~p"/organizacja/przelacz"}
            class="w-full"
          >
            <input type="hidden" name="organizacja" value={organization.id} />
            <FirmowidUI.Components.Button.button
              type="submit"
              variant="unstyled"
              class={[
                "w-full cursor-pointer text-left",
                account_menu_org_styles(),
                account_menu_hover_styles()
              ]}
              title={organization.display_name}
            >
              <.org_avatar name={organization.display_name} class="bg-grey-800 text-white" />
              <span class="min-w-0 flex-1 truncate">{organization.display_name}</span>
            </FirmowidUI.Components.Button.button>
          </.form>
        <% else %>
          <div
            id={"unavailable-organization-#{organization.id}"}
            class={["text-grey-500", account_menu_org_styles()]}
            title={organization.display_name}
          >
            <.org_avatar name={organization.display_name} class="bg-grey-900 text-grey-500" />
            <span class="min-w-0 flex-1 truncate">{organization.display_name}</span>
            <span class="shrink-0 text-xs">{pgettext("avatar menu", "No plan")}</span>
          </div>
        <% end %>
      <% end %>
      <.link
        kind="unstyled"
        navigate={~p"/organizacja"}
        class={["text-grey-500 hover:bg-grey-900 hover:text-white", account_menu_org_styles()]}
      >
        <span
          class="flex size-6 shrink-0 items-center justify-center rounded-sm border border-dashed border-grey-700 text-grey-300"
          aria-hidden="true"
        >
          <.figma_icon name="create" class="size-3.5 stroke-[2.57]" />
        </span>
        {pgettext("avatar menu", "Add organization")}
      </.link>
    </div>
    <.account_menu_separator />
    <div class="flex flex-col gap-0.5">
      <.link kind="unstyled" navigate={~p"/ustawienia"} class={account_menu_item_styles()}>
        {pgettext("avatar menu", "Settings")}
      </.link>
      <.link
        :if={@current_user.member.role == :admin}
        kind="unstyled"
        navigate={~p"/ustawienia/konta-bankowe"}
        class={account_menu_item_styles()}
      >
        {pgettext("avatar menu", "Bank accounts")}
      </.link>
      <.link
        :if={@current_user.system_role == :superuser}
        kind="unstyled"
        navigate={~p"/admin/rozliczenia"}
        class={account_menu_item_styles()}
      >
        {pgettext("avatar menu", "Superadmin panel")}
      </.link>
    </div>
    <.account_menu_separator />
    <.form
      for={%{}}
      id="app-logout-form"
      action={~p"/wyloguj"}
      method="delete"
      class="w-full"
      data-posthog-reset-on-submit="true"
    >
      <FirmowidUI.Components.Button.button
        type="submit"
        variant="unstyled"
        class={["w-full cursor-pointer", account_menu_item_styles()]}
      >
        <span class="min-w-0 flex-1 truncate">{pgettext("avatar menu", "Log out")}</span>
        <.figma_icon name="wyloguj" class="size-4.5" />
      </FirmowidUI.Components.Button.button>
    </.form>
    """
  end

  defp account_menu_separator(assigns) do
    ~H"""
    <div class="py-1.5" aria-hidden="true">
      <div class="h-px bg-grey-800"></div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: nil

  # A 24 px square with the organization's initials, e.g. "KZ" for Kawiarnia Ziarno.
  defp org_avatar(assigns) do
    ~H"""
    <span
      class={[
        "flex size-6 shrink-0 items-center justify-center rounded-sm text-[10px] leading-none font-semibold",
        @class
      ]}
      aria-hidden="true"
    >
      {initials(@name)}
    </span>
    """
  end

  defp initials(name) do
    name
    |> to_string()
    |> String.split(~r/[\s\-–]+/u, trim: true)
    |> Enum.filter(&String.match?(&1, ~r/^\p{L}/u))
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp account_menu_org_styles,
    do:
      "flex h-9 items-center gap-2.5 rounded-[2px] px-2 text-sm/[18px] transition-colors duration-100 motion-reduce:transition-none"

  defp account_menu_hover_styles, do: "text-grey-300 hover:bg-grey-900 hover:text-white active:bg-grey-800"

  defp account_menu_item_styles,
    do: [
      "flex h-8 items-center gap-3 rounded-[2px] px-2 text-left text-sm/[18px] transition-colors duration-100 motion-reduce:transition-none",
      account_menu_hover_styles()
    ]

  # A member works inside the app navigation, except on a `focused` page of its own (onboarding).
  defp app_navigation?(assigns) do
    match?(%{member: %{organization_id: _}}, assigns[:current_user]) and is_nil(assigns[:focused])
  end

  defp impersonating?(%Firmowid.Core.User{} = user), do: not is_nil(Firmowid.Core.impersonator_id(user))

  defp impersonating?(_user), do: false

  defp posthog_enabled?(current_user) do
    Keyword.get(
      Application.get_env(:firmowid, :frontend_observability, []),
      :posthog_enabled,
      false
    ) and
      not impersonating?(current_user)
  end

  @doc """
  Builds canonical URL for the currently rendered page.
  """
  @spec canonical_url(map()) :: String.t()
  def canonical_url(assigns) do
    Endpoint.url() <> canonical_path(assigns)
  end

  defp canonical_path(assigns) do
    case assigns[:current_uri] do
      %URI{path: path} when is_binary(path) and path != "" ->
        path

      _ ->
        case assigns[:conn] do
          %{request_path: request_path} when is_binary(request_path) and request_path != "" ->
            request_path

          _ ->
            "/"
        end
    end
  end

  defp meta_description(assigns) do
    assigns[:meta_description] ||
      gettext(
        "Firmowid helps Polish companies issue KSeF-compliant invoices, sync their bank, track working time and settle with the team in one place."
      )
  end

  # Search results cut titles at about 60 characters, so the brand suffix goes only on short ones.
  @title_suffix_max_length 50

  defp meta_title(assigns) do
    title = assigns[:page_title] || "Firmowid"

    if String.contains?(title, "Firmowid") or String.length(title) > @title_suffix_max_length,
      do: title,
      else: title <> " · Firmowid"
  end

  defp social_image(%{article: %{image: %{} = image} = article}) do
    %{
      url: Endpoint.url() <> Endpoint.static_path(image.path),
      width: image.width,
      height: image.height,
      alt: article.title
    }
  end

  defp social_image(_assigns) do
    %{
      url: Endpoint.url() <> Endpoint.static_path("/images/og/home.png"),
      width: 1200,
      height: 630,
      alt: gettext("Firmowid - free KSeF invoices, banking and team time tracking")
    }
  end

  # sobelow_skip ["XSS.Raw"]
  # Jason's html_safe encoding escapes closing script tags before marking JSON-LD as safe HTML.
  defp structured_data(assigns) do
    base_url = Endpoint.url()
    image = social_image(assigns)
    organization_id = base_url <> "/#organization"
    website_id = base_url <> "/#website"
    application_id = base_url <> "/#application"
    legal_entity = Application.fetch_env!(:firmowid, :legal_entity)

    graph = [
      %{
        "@type" => "Organization",
        "@id" => organization_id,
        "name" => legal_entity.name,
        "legalName" => legal_entity.official_name,
        "address" => legal_entity.address,
        "taxID" => legal_entity.nip,
        "url" => "https://alergeek.ventures",
        "brand" => %{
          "@type" => "Brand",
          "name" => "Firmowid",
          "logo" => base_url <> Endpoint.static_path("/images/favicon.png")
        }
      },
      %{
        "@type" => "WebSite",
        "@id" => website_id,
        "url" => base_url <> "/",
        "name" => "Firmowid",
        "inLanguage" => "pl-PL",
        "publisher" => %{"@id" => organization_id}
      },
      %{
        "@type" => "WebPage",
        "@id" => canonical_url(assigns) <> "#webpage",
        "url" => canonical_url(assigns),
        "name" => meta_title(assigns),
        "description" => meta_description(assigns),
        "inLanguage" => "pl-PL",
        "isPartOf" => %{"@id" => website_id},
        "about" => %{"@id" => application_id},
        "primaryImageOfPage" => %{
          "@type" => "ImageObject",
          "url" => image.url,
          "width" => image.width,
          "height" => image.height
        }
      },
      %{
        "@type" => "WebApplication",
        "@id" => application_id,
        "name" => "Firmowid",
        "url" => base_url <> "/",
        "applicationCategory" => "BusinessApplication",
        "operatingSystem" => "Web",
        "inLanguage" => "pl-PL",
        "publisher" => %{"@id" => organization_id},
        "sameAs" => [
          "https://github.com/Alergeek-Ventures/firmowid",
          "https://pl.linkedin.com/showcase/firmowid/",
          "https://x.com/firmowid"
        ],
        "isAccessibleForFree" => true,
        "license" => "https://www.gnu.org/licenses/agpl-3.0.html",
        "offers" => %{
          "@type" => "Offer",
          "price" => "0",
          "priceCurrency" => "PLN",
          "url" => base_url <> "/cennik"
        }
      }
    ]

    graph =
      graph ++
        GuideStructuredData.nodes(assigns, %{
          url: canonical_url(assigns),
          base_url: base_url,
          organization_id: organization_id,
          image_url: image.url
        })

    %{"@context" => "https://schema.org", "@graph" => graph}
    |> Jason.encode!(escape: :html_safe)
    |> Phoenix.HTML.raw()
  end
end
