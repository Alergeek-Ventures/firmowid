defmodule FirmowidWeb.Infrastructure.Components.ErrorHtml do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  def render("404.html", assigns) do
    ~H"""
    <div class="bg-lightGreyBg flex h-full flex-col">
      <.navbar class="sticky inset-x-0 top-0 z-50 py-4">
        <.navbar_logo navigate={~p"/"} />
      </.navbar>
      <main class="flex flex-1 items-center justify-center p-8">
        <div class="max-w-md text-center">
          <p class="mb-2 text-6xl font-extrabold text-black/20">404</p>
          <h1 class="mb-2 text-xl font-bold">Nie znaleziono strony</h1>
          <p class="mb-6 text-sm text-black/50">
            Strona, której szukasz, nie istnieje lub została przeniesiona.
          </p>
          <.link kind="unstyled" navigate={~p"/"} class="text-sm underline">
            Wróć do strony głównej
          </.link>
        </div>
      </main>
    </div>
    """
  end

  def render("500.html", assigns) do
    ~H"""
    <div class="bg-lightGreyBg flex h-full flex-col">
      <.navbar class="sticky inset-x-0 top-0 z-50 py-4">
        <.navbar_logo navigate={~p"/"} />
      </.navbar>
      <main class="flex flex-1 items-center justify-center p-8">
        <div class="max-w-md text-center">
          <p class="mb-2 text-6xl font-extrabold text-black/20">500</p>
          <h1 class="mb-2 text-xl font-bold">Wystąpił błąd serwera</h1>
          <p class="mb-6 text-sm text-black/50">
            Błąd został automatycznie zgłoszony — nasz zespół zajmie się nim jak najszybciej.
          </p>
          <.link kind="unstyled" navigate={~p"/"} class="text-sm underline">
            Wróć do strony głównej
          </.link>
        </div>
      </main>
    </div>
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
