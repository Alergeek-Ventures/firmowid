defmodule FirmowidWeb.Infrastructure.Components.ErrorHtmlTest do
  use FirmowidWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  alias FirmowidWeb.Infrastructure.Components.ErrorHtml

  test "renders 404.html" do
    assert render_to_string(ErrorHtml, "404", "html", []) =~ "Nie znaleziono strony"
  end

  test "renders 500.html" do
    assert render_to_string(ErrorHtml, "500", "html", []) =~
             "Błąd został automatycznie zgłoszony"
  end
end
