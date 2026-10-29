defmodule FirmowidWeb.Infrastructure.Components.ErrorHtml do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  def render("404.html", assigns) do
    ~H"""
    <div class="flex h-full flex-col bg-grey-100">
      <.navbar class="sticky inset-x-0 top-0 z-50 py-4">
        <.navbar_logo navigate={~p"/"} />
      </.navbar>
      <main class="flex flex-1 items-center justify-center p-8">
        <div class="max-w-md text-center">
          <p class="mb-2 text-3xl font-extrabold text-black/20">404</p>
          <h1 class="mb-2 text-xl font-bold">{gettext("Page not found")}</h1>
          <p class="mb-6 text-sm text-black/50">
            {gettext("The page you are looking for does not exist or has been moved.")}
          </p>
          <.link kind="unstyled" navigate={~p"/"} class="text-sm underline">
            {gettext("Back to the home page")}
          </.link>
        </div>
      </main>
    </div>
    """
  end

  def render("500.html", assigns) do
    ~H"""
    <div class="flex h-full flex-col bg-grey-100">
      <.navbar class="sticky inset-x-0 top-0 z-50 py-4">
        <.navbar_logo navigate={~p"/"} />
      </.navbar>
      <main class="flex flex-1 items-center justify-center p-8">
        <div class="max-w-md text-center">
          <p class="mb-2 text-3xl font-extrabold text-black/20">500</p>
          <h1 class="mb-2 text-xl font-bold">{gettext("A server error occurred")}</h1>
          <p class="mb-6 text-sm text-black/50">
            {gettext(
              "The error has been reported automatically — our team will look into it as soon as possible."
            )}
          </p>
          <.link kind="unstyled" navigate={~p"/"} class="text-sm underline">
            {gettext("Back to the home page")}
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
