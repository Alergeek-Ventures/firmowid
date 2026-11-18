defmodule FirmowidWeb.Landing.Utilities.GuideStructuredData do
  @moduledoc """
  JSON-LD nodes for the guide index and guide articles: Article, BreadcrumbList,
  FAQPage and the index's ItemList. The root layout adds them to the site graph.
  """

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
              "url" => base_url <> guide.path
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
    crumbs =
      [%{name: "Firmowid", path: "/"}] ++
        article.breadcrumbs ++ [%{name: article.title, path: nil}]

    %{
      "@type" => "BreadcrumbList",
      "@id" => url <> "#breadcrumb",
      "itemListElement" =>
        crumbs
        |> Enum.with_index(1)
        |> Enum.map(fn
          {%{name: name, path: nil}, position} ->
            %{"@type" => "ListItem", "position" => position, "name" => name}

          {%{name: name, path: path}, position} ->
            %{
              "@type" => "ListItem",
              "position" => position,
              "name" => name,
              "item" => base_url <> path
            }
        end)
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
