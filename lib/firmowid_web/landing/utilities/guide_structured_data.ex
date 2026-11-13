defmodule FirmowidWeb.Landing.Utilities.GuideStructuredData do
  @moduledoc """
  JSON-LD nodes for the guide index and guide articles: Article, BreadcrumbList,
  FAQPage and the index's ItemList. The root layout adds them to the site graph.
  """

  use Gettext, backend: Firmowid.Gettext

  @type context :: %{
          url: String.t(),
          base_url: String.t(),
          organization_id: String.t(),
          image_url: String.t()
        }

  @doc """
  Returns the nodes for a page: an article's nodes when `:article` is set, the
  index's ItemList when `:guide_categories` is set, and none on other pages.
  """
  @spec nodes(map(), context()) :: [map()]
  def nodes(assigns, context) do
    article_nodes(assigns[:article], context) ++ index_nodes(assigns[:guide_categories], context)
  end

  defp article_nodes(nil, _context), do: []

  defp article_nodes(article, context) do
    [article(article, context), breadcrumbs(article, context)] ++ faq(article, context)
  end

  defp index_nodes(nil, _context), do: []

  defp index_nodes(guide_categories, %{url: url, base_url: base_url}) do
    guides = Enum.flat_map(guide_categories, fn {_category, guides} -> guides end)

    [
      %{
        "@type" => "ItemList",
        "@id" => url <> "#guides",
        "numberOfItems" => length(guides),
        "itemListElement" =>
          guides
          |> Enum.with_index(1)
          |> Enum.map(fn {guide, position} ->
            %{
              "@type" => "ListItem",
              "position" => position,
              "name" => guide.title,
              "url" => base_url <> "/poradnik/" <> guide.slug
            }
          end)
      }
    ]
  end

  defp article(article, %{url: url, organization_id: organization_id, image_url: image_url}) do
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
      "image" => image_url
    }
  end

  defp breadcrumbs(article, %{url: url, base_url: base_url}) do
    %{
      "@type" => "BreadcrumbList",
      "@id" => url <> "#breadcrumb",
      "itemListElement" => [
        %{
          "@type" => "ListItem",
          "position" => 1,
          "name" => "Firmowid",
          "item" => base_url <> "/"
        },
        %{
          "@type" => "ListItem",
          "position" => 2,
          "name" => gettext("Guides"),
          "item" => base_url <> "/poradnik"
        },
        %{
          "@type" => "ListItem",
          "position" => 3,
          "name" => article.category.name,
          "item" => base_url <> "/poradnik#" <> article.category.slug
        },
        %{"@type" => "ListItem", "position" => 4, "name" => article.title}
      ]
    }
  end

  defp faq(%{faq: [_ | _] = faq}, %{url: url}) do
    [
      %{
        "@type" => "FAQPage",
        "@id" => url <> "#faq",
        "mainEntity" =>
          Enum.map(faq, fn entry ->
            %{
              "@type" => "Question",
              "name" => entry.question,
              "acceptedAnswer" => %{"@type" => "Answer", "text" => entry.answer}
            }
          end)
      }
    ]
  end

  defp faq(_article, _context), do: []
end
