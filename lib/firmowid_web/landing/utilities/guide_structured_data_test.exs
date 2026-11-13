defmodule FirmowidWeb.Landing.Utilities.GuideStructuredDataTest do
  use ExUnit.Case, async: true

  alias FirmowidWeb.Landing.Utilities.Guides
  alias FirmowidWeb.Landing.Utilities.GuideStructuredData

  @context %{
    url: "https://firmowid.example/poradnik/x",
    base_url: "https://firmowid.example",
    organization_id: "https://firmowid.example/#organization",
    image_url: "https://firmowid.example/images/x.png"
  }

  defp types(nodes), do: Enum.map(nodes, & &1["@type"])

  test "an article with a questions section gets Article, BreadcrumbList and FAQPage" do
    {:ok, guide} = Guides.fetch("tryb-offline-ksef")

    nodes = GuideStructuredData.nodes(%{article: guide}, @context)

    assert types(nodes) == ["Article", "BreadcrumbList", "FAQPage"]
    faq = Enum.find(nodes, &(&1["@type"] == "FAQPage"))
    assert length(faq["mainEntity"]) == length(guide.faq)
    assert Enum.all?(faq["mainEntity"], &(&1["acceptedAnswer"]["text"] != ""))
  end

  test "an article without a questions section has no FAQPage" do
    {:ok, guide} = Guides.fetch("limit-10000-ksef")

    assert types(GuideStructuredData.nodes(%{article: guide}, @context)) == [
             "Article",
             "BreadcrumbList"
           ]
  end

  test "the index lists every guide in page order" do
    categories = Guides.by_category()

    assert [list] = GuideStructuredData.nodes(%{guide_categories: categories}, @context)
    assert list["@type"] == "ItemList"
    assert list["numberOfItems"] == length(Guides.all())

    assert Enum.map(list["itemListElement"], & &1["position"]) ==
             Enum.to_list(1..length(Guides.all()))
  end

  test "other pages get nothing" do
    assert GuideStructuredData.nodes(%{}, @context) == []
  end
end
