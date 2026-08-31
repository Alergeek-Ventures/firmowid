defmodule FirmowidWeb.DesignSystem.Components.CoreComponentsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest

  alias FirmowidWeb.DesignSystem.Components.CoreComponents

  test "renders the plain variant with its legacy wrapper and navigate target" do
    html = render_back(%{navigate: "/posts", variant: :plain, label: "Wróć do wpisów"})

    assert html =~ "mt-16"
    assert html =~ "href=\"/posts\""
    assert html =~ "data-phx-link=\"redirect\""
    assert html =~ "hero-arrow-left-solid"
    assert html =~ "Wróć do wpisów"
  end

  test "renders a labeled circular chevron link with a patch target" do
    html =
      render_back(%{
        navigate: nil,
        patch: "/faktury/kreator?krok=1",
        variant: :circle_chevron,
        class: "absolute text-sm",
        label: "Wróć"
      })

    assert html =~ "href=\"/faktury/kreator?krok=1\""
    assert html =~ "data-phx-link=\"patch\""
    assert html =~ "absolute text-sm"
    assert html =~ "Wróć"
    assert html =~ "lucide-circle-chevron-left"
  end

  test "renders an accessible icon-only circular arrow link" do
    html =
      render_component(&CoreComponents.back/1,
        navigate: "/faktury",
        variant: :circle_arrow,
        aria_label: "Wróć do faktur",
        icon_class: "size-7"
      )

    assert html =~ "aria-label=\"Wróć do faktur\""
    assert html =~ "hero-arrow-left-circle-solid"
    assert html =~ "size-7"
    refute html =~ ">Wróć<"
  end

  test "renders the delegation variant" do
    html = render_back(%{navigate: "/delegacje", variant: :delegation, label: "Wróć"})

    assert html =~ "size-6"
    assert html =~ "rounded-full bg-black text-white"
    assert html =~ "lucide-chevron-left"
    assert html =~ "Wróć"
  end

  defp render_back(assigns) do
    assigns =
      Map.merge(
        %{navigate: nil, patch: nil, class: nil, icon_class: nil, aria_label: "Wróć"},
        assigns
      )

    render_component(&labeled_back/1, assigns)
  end

  defp labeled_back(assigns) do
    ~H"""
    <CoreComponents.back
      navigate={@navigate}
      patch={@patch}
      variant={@variant}
      class={@class}
      icon_class={@icon_class}
      aria_label={@aria_label}
    >
      {@label}
    </CoreComponents.back>
    """
  end
end
