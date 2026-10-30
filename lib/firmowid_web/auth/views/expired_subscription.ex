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
         |> assign(:page_title, gettext("Subscription expired"))
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
        <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-rust-100 text-rust-700">
          <Lucideicons.shield_alert class="size-6" />
        </div>
        <h1 class="mb-2 text-2xl/tight font-semibold">
          {gettext("Subscription expired")}
        </h1>
        <p :if={@organization_name} class="mb-2 text-sm font-medium text-grey-900">
          {@organization_name}
        </p>
        <p class="text-base/snug text-grey-700">
          {gettext(
            "Access to the organization has been temporarily blocked because the subscription has expired. Write to us to renew access."
          )}
        </p>

        <div class="mt-6 space-y-3">
          <.link kind="button" mailto={@contact_mailto} variant="primary" class="w-full sm:w-auto">
            {gettext("Contact us about the subscription")}
          </.link>

          <p class="text-sm text-grey-700">
            {gettext("If the button does not work, write to:")}
            <.link kind="unstyled" mailto={@contact_email} class="font-semibold underline">
              {@contact_email}
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp contact_mailto(nil), do: "#{@contact_email}?subject=#{gettext("Subscription expired")}"

  defp contact_mailto(org_name) do
    subject = gettext("Subscription expired - %{organization}", organization: org_name)
    "#{@contact_email}?subject=#{subject}"
  end
end
