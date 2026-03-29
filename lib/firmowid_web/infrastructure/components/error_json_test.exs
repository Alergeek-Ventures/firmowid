defmodule FirmowidWeb.Infrastructure.Components.ErrorJsonTest do
  use FirmowidWeb.ConnCase, async: true

  alias FirmowidWeb.Infrastructure.Components.ErrorJson

  test "renders 404" do
    assert ErrorJson.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ErrorJson.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
