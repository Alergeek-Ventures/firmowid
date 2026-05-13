defmodule FirmowidWeb.Auth.Views.ExpiredSubscription do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Infrastructure.UserAuth

  @contact_email "contact@alergeek.ventures"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      case socket.assigns[:current_user] do
        %{organization_id: organization_id} = user when not is_nil(organization_id) ->
          {loaded_user, org, _scope} = UserAuth.load_scope_and_avatars(user)

          socket
          |> assign(:current_user, loaded_user)
          |> assign(:current_org, org)

        _user ->
          socket
      end

    socket = assign(socket, :page_title, "Abonament wygasł")

    case UserAuth.blocked_page_action(
           :expired_subscription,
           socket.assigns[:current_user],
           socket.assigns[:current_org]
         ) do
      :ok ->
        {:ok,
         socket
         |> assign(:contact_email, @contact_email)
         |> assign(:contact_mailto, contact_mailto(socket.assigns.current_org.name))}

      {:redirect, target} ->
        if connected?(socket) do
          {:ok, push_navigate(socket, to: target)}
        else
          {:ok, Phoenix.LiveView.redirect(socket, to: target)}
        end
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
        <h1 class="mb-2 text-2xl/tight font-semibold">Abonament wygasł</h1>
        <p class="text-grey-900 mb-2 text-sm font-medium">{@current_org.name}</p>
        <p class="text-grey-700 text-base/snug">
          Dostęp do organizacji został tymczasowo zablokowany z powodu wygaśnięcia abonamentu.
          Napisz do nas, aby odnowić dostęp.
        </p>

        <div class="mt-6 space-y-3">
          <.link kind="button" mailto={@contact_mailto} variant="primary" class="w-full sm:w-auto">
            Skontaktuj się w sprawie abonamentu
          </.link>

          <p class="text-grey-700 text-sm">
            Jeśli przycisk nie działa, napisz na:
            <.link kind="unstyled" mailto={@contact_email} class="font-semibold underline">
              {@contact_email}
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp contact_mailto(org_name), do: "#{@contact_email}?subject=Abonament wygasł - #{org_name}"
end
