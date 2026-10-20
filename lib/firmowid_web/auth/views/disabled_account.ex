defmodule FirmowidWeb.Auth.Views.DisabledAccount do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias FirmowidWeb.Infrastructure.UserAuth

  # Shown after a sign-in attempt by an archived account or a member of an organization
  # without a billing plan; such accounts never hold a session.
  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns[:current_user] do
      nil -> {:ok, assign(socket, :page_title, "Konto wyłączone")}
      user -> {:ok, redirect(socket, to: UserAuth.signed_in_path_for_user(user))}
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
        <p class="text-base/snug text-grey-700">
          To konto jest obecnie niedostępne. Skontaktuj się z administratorem organizacji,
          aby potwierdzić, czy konto zostało wyłączone lub dostęp został zablokowany.
        </p>
      </div>
    </div>
    """
  end
end
