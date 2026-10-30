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
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.Infrastructure.Flags
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Core.Endpoint

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
            variant="secondary"
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

  attr :current_user, :map, required: true
  attr :current_uri, URI, required: true
  attr :analysis_enabled, :boolean, required: true

  attr :variant, :atom,
    default: :bar,
    values: [:bar, :menu],
    doc: "`:bar` for the desktop navbar row, `:menu` for the mobile menu list"

  defp main_navigation_links(assigns) do
    path = assigns.current_uri.path

    assigns =
      assign(assigns,
        invoicing?:
          not Enum.any?(
            ["/analiza", "/czasosledz", "/zarzadzanie"],
            &String.starts_with?(path, &1)
          ),
        management?: String.starts_with?(path, "/zarzadzanie"),
        analysis?: String.starts_with?(path, "/analiza"),
        time_tracking?: String.starts_with?(path, "/czasosledz")
      )

    ~H"""
    <.link
      :if={@current_user.member.role != :employee}
      kind="unstyled"
      navigate={~p"/fakturowanie"}
      class={navigation_link_styles(@variant, @invoicing?)}
    >
      <.icon name="hero-clipboard-document-list" class="size-5" />{pgettext(
        "main navigation",
        "Invoicing"
      )}
    </.link>
    <%= if @current_user.member.role == :admin do %>
      <.link
        kind="unstyled"
        navigate={~p"/zarzadzanie/pracownicy"}
        class={navigation_link_styles(@variant, @management?)}
      >
        <.icon name="hero-presentation-chart-line" class="size-5" />{pgettext(
          "main navigation",
          "Management"
        )}
      </.link>
      <.link
        :if={@analysis_enabled}
        kind="unstyled"
        navigate={~p"/analiza"}
        class={navigation_link_styles(@variant, @analysis?)}
      >
        <.icon name="hero-scale" class="size-5" />{pgettext("main navigation", "Analysis")}
        <span
          id={"analiza-beta-#{@variant}"}
          class="ml-1 rounded bg-white/20 px-1.5 py-0.5 text-xs"
          phx-hook="Tippy"
          data-tippy-content={
            gettext(
              "This feature is still in progress! Your feedback will help us make it even better."
            )
          }
        >
          BETA
        </span>
      </.link>
    <% end %>
    <.link
      kind="unstyled"
      navigate={~p"/czasosledz"}
      class={navigation_link_styles(@variant, @time_tracking?)}
    >
      <.icon name="hero-clock" class="size-5" />{pgettext("main navigation", "Time tracking")}
    </.link>
    """
  end

  defp navigation_link_styles(:bar, active?) do
    [
      active? && "opacity-90",
      "flex items-center gap-1 opacity-50 transition-all hover:opacity-100"
    ]
  end

  defp navigation_link_styles(:menu, active?) do
    [
      active? && "bg-grey-700/50",
      "flex items-center gap-2 rounded-md p-2 uppercase hover:bg-grey-700/50"
    ]
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

  defp meta_title(assigns) do
    title = assigns[:page_title] || "Firmowid"
    if String.contains?(title, "Firmowid"), do: title, else: title <> " · Firmowid"
  end

  defp social_image_url do
    Endpoint.url() <> Endpoint.static_path("/images/social-card.png")
  end

  # sobelow_skip ["XSS.Raw"]
  # Jason's html_safe encoding escapes closing script tags before marking JSON-LD as safe HTML.
  defp structured_data(assigns) do
    base_url = Endpoint.url()
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
          "url" => social_image_url(),
          "width" => 1200,
          "height" => 630
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
        "offers" => %{
          "@type" => "Offer",
          "price" => "0",
          "priceCurrency" => "PLN",
          "url" => base_url <> "/cennik"
        }
      }
    ]

    graph = graph ++ article_data(assigns[:article], canonical_url(assigns), organization_id)

    %{"@context" => "https://schema.org", "@graph" => graph}
    |> Jason.encode!(escape: :html_safe)
    |> Phoenix.HTML.raw()
  end

  defp article_data(nil, _url, _organization_id), do: []

  defp article_data(article, url, organization_id) do
    [
      %{
        "@type" => "Article",
        "@id" => url <> "#article",
        "headline" => article.title,
        "description" => article.description,
        "datePublished" => Date.to_iso8601(article.published),
        "dateModified" => Date.to_iso8601(article.updated),
        "inLanguage" => "pl-PL",
        "mainEntityOfPage" => %{"@id" => url <> "#webpage"},
        "author" => %{"@id" => organization_id},
        "publisher" => %{"@id" => organization_id},
        "image" => social_image_url()
      }
    ]
  end
end
