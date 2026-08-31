defmodule FirmowidWeb.DesignSystem.Components.CoreComponentsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest

  alias FirmowidWeb.DesignSystem.Components.CoreComponents

  test "renders the filled link with a custom label and navigate target" do
    html = render_back(%{navigate: "/posts", label: "Wróć do wpisów"})

    assert html =~ "href=\"/posts\""
    assert html =~ "data-phx-link=\"redirect\""
    assert html =~ "rounded-full bg-black text-white"
    assert html =~ "lucide-chevron-left"
    assert html =~ "Wróć do wpisów"
  end

  test "renders the default label on a link with a patch target" do
    html =
      render_component(&CoreComponents.back/1,
        patch: "/faktury/kreator?krok=1",
        class: "absolute text-sm"
      )

    assert html =~ "href=\"/faktury/kreator?krok=1\""
    assert html =~ "data-phx-link=\"patch\""
    assert html =~ "absolute text-sm"
    assert html =~ "Wróć"
  end

  test "renders an accessible icon-only link" do
    html =
      render_component(&CoreComponents.back/1,
        navigate: "/faktury",
        icon_only: true,
        aria_label: "Wróć do faktur"
      )

    assert html =~ "aria-label=\"Wróć do faktur\""
    assert html =~ "rounded-full bg-black text-white"
    assert html =~ "lucide-chevron-left"
    refute html =~ ">Wróć<"
  end

  test "renders the default label" do
    html = render_component(&CoreComponents.back/1, navigate: "/delegacje")

    assert html =~ "size-6"
    assert html =~ "rounded-full bg-black text-white"
    assert html =~ "lucide-chevron-left"
    assert html =~ "Wróć"
  end

  defp render_back(assigns) do
    assigns =
      Map.merge(
        %{navigate: nil, patch: nil, class: nil, icon_only: false, aria_label: "Wróć"},
        assigns
      )

    render_component(&labeled_back/1, assigns)
  end

  defp labeled_back(assigns) do
    ~H"""
    <CoreComponents.back
      navigate={@navigate}
      patch={@patch}
      class={@class}
      icon_only={@icon_only}
      aria_label={@aria_label}
    >
      {@label}
    </CoreComponents.back>
    """
  end
end
