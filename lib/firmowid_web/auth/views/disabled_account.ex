defmodule FirmowidWeb.Auth.Views.DisabledAccount do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias FirmowidWeb.Infrastructure.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    socket =
      case socket.assigns[:current_user] do
        nil ->
          socket

        user ->
          loaded_user =
            Ash.load!(user, [avatar_blob: [:url]],
              actor: user,
              tenant: user.organization_id
            )

          assign(socket, :current_user, loaded_user)
      end

    # If a non-archived user somehow reached this page, redirect them to their
    # normal signed-in path.
    socket = assign(socket, :page_title, "Konto wyłączone")

    if socket.assigns[:current_user] && not UserAuth.archived_user?(socket.assigns.current_user) do
      target = UserAuth.signed_in_path_for_user(socket.assigns.current_user)

      if connected?(socket) do
        {:ok, push_navigate(socket, to: target)}
      else
        {:ok, Phoenix.LiveView.redirect(socket, to: target)}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex min-h-[60vh] w-full max-w-3xl items-center justify-center px-6 py-16">
      <div class="w-full max-w-xl rounded-lg bg-white p-8 text-center shadow">
        <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-orange-100 text-orange-700">
          <Lucideicons.shield_alert class="size-6" />
        </div>
        <h1 class="mb-2 text-2xl/tight font-semibold">Konto wyłączone</h1>
        <p class="text-grey-700 text-base/snug">
          To konto zostało wyłączone. Skontaktuj się z administratorem organizacji,
          aby je odblokować.
        </p>
      </div>
    </div>
    """
  end
end
