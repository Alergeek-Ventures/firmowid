defmodule FirmowidWeb.Auth.Views.ExpiredSubscription do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Infrastructure.UserAuth

  @contact_email "contact@alergeek.ventures"

  # Shown after the owner of an organization without a billing plan signs in; the
  # account gets no session, so the sign-in callback passes the organization name.
  @impl true
  def mount(params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        organization_name = params["organizacja"]

        {:ok,
         socket
         |> assign(:page_title, "Abonament wygasł")
         |> assign(:organization_name, organization_name)
         |> assign(:contact_email, @contact_email)
         |> assign(:contact_mailto, contact_mailto(organization_name))}

      user ->
        {:ok, redirect(socket, to: UserAuth.signed_in_path_for_user(user))}
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
        <p :if={@organization_name} class="mb-2 text-sm font-medium text-grey-900">
          {@organization_name}
        </p>
        <p class="text-base/snug text-grey-700">
          Dostęp do organizacji został tymczasowo zablokowany z powodu wygaśnięcia abonamentu.
          Napisz do nas, aby odnowić dostęp.
        </p>

        <div class="mt-6 space-y-3">
          <.link kind="button" mailto={@contact_mailto} variant="primary" class="w-full sm:w-auto">
            Skontaktuj się w sprawie abonamentu
          </.link>

          <p class="text-sm text-grey-700">
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

  defp contact_mailto(nil), do: "#{@contact_email}?subject=Abonament wygasł"
  defp contact_mailto(org_name), do: "#{@contact_email}?subject=Abonament wygasł - #{org_name}"
end
