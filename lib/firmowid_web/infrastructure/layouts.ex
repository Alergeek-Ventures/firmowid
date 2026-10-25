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

  @default_meta_description "Firmowid pomaga polskim firmom wystawiać faktury zgodne z KSeF, synchronizować bank, ewidencjonować czas pracy i rozliczać zespół w jednym miejscu."

  embed_templates "layouts/*"

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
    assigns[:meta_description] || @default_meta_description
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

    %{"@context" => "https://schema.org", "@graph" => graph}
    |> Jason.encode!(escape: :html_safe)
    |> Phoenix.HTML.raw()
  end
end
