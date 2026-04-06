defmodule FirmowidWeb.Infrastructure.Hooks.RequireOrganization do
  @moduledoc """
  LiveView on_mount hook. Requires authenticated user with an organization.

  After ash_authentication_live_session populates `current_user`, this hook:
  1. Redirects to /zaloguj if no user
  2. Redirects to /organization if user has no org
  3. Loads avatar on user and organization via Ash.load!
  4. Assigns current_user, current_org, ash_scope
  """

  use FirmowidWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Firmowid.Ash.Scope

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, "Musisz się zalogować.")
         |> redirect(to: ~p"/zaloguj")}

      %{organization_id: nil} ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, "Aby przejść dalej, przypisz sobie organizację.")
         |> redirect(to: ~p"/organization")}

      user ->
        user =
          Ash.load!(user, [:organization, avatar_blob: [:url]],
            tenant: user.organization_id,
            authorize?: false,
            actor: %{}
          )

        org =
          Ash.load!(user.organization, [avatar_blob: [:url]],
            tenant: user.organization_id,
            authorize?: false,
            actor: %{}
          )

        scope = %Scope{actor: user, tenant: user.organization_id}

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_org, org)
         |> assign(:ash_scope, scope)}
    end
  end
end
