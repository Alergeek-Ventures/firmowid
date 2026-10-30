defmodule FirmowidWeb.Admin.Controllers.Impersonation do
  @moduledoc """
  Lets a superuser use the application as an organization's owner and return to
  their own session.

  The owner's session token carries `Firmowid.Core.impersonation_claims/1`, so it
  is not recorded as the owner's sign-in and analytics skip it; the superuser's
  token waits in the session until they return.
  """
  use FirmowidWeb, :controller

  alias AshAuthentication.Jwt
  alias AshAuthentication.Phoenix.Controller, as: AuthenticationController
  alias AshAuthentication.Plug.Helpers
  alias Firmowid.Core
  alias FirmowidWeb.Admin.Utilities.Navigation
  alias FirmowidWeb.Infrastructure.UserAuth

  @superuser_token_key "impersonator_token"

  @doc "Signs the superuser in as the owner of the `org_id` organization."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"org_id" => organization_id}) do
    case get_session(conn, @superuser_token_key) do
      nil ->
        impersonate(conn, organization_id)

      # Already in a session as an owner who is a superuser too: their token would
      # replace the superuser's own one.
      _superuser_token ->
        redirect(conn, to: Navigation.settlement_path(organization_id))
    end
  end

  defp impersonate(conn, organization_id) do
    superuser = conn.assigns.current_user

    %{owner: owner} =
      Core.get_organization!(organization_id,
        actor: superuser,
        tenant: organization_id,
        load: [:owner]
      )

    {:ok, token, _claims} = Jwt.token_for_user(owner, Core.impersonation_claims(superuser))

    conn
    |> clear_session()
    |> put_session(@superuser_token_key, superuser.__metadata__.token)
    |> put_session(UserAuth.organization_session_key(), organization_id)
    |> sign_in(owner, token)
    |> redirect(to: UserAuth.signed_in_path_for_user(owner, organization_id))
  end

  @doc "Ends the session as the owner and restores the superuser's own session."
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    case get_session(conn, @superuser_token_key) do
      # Already ended, e.g. in another tab.
      nil ->
        redirect(conn, to: ~p"/")

      token ->
        organization_id = get_session(conn, UserAuth.organization_session_key())

        conn
        |> Helpers.revoke_session_tokens(:firmowid)
        |> clear_session()
        |> restore_superuser(token, organization_id)
    end
  end

  # The superuser's token expires like any session; then they sign in again.
  defp restore_superuser(conn, token, organization_id) do
    with {:ok, %{"sub" => subject}, resource} <- Jwt.verify(token, :firmowid),
         {:ok, superuser} <- AshAuthentication.subject_to_user(subject, resource) do
      conn
      |> sign_in(superuser, token)
      |> redirect(to: Navigation.settlement_path(organization_id))
    else
      _ -> redirect(conn, to: ~p"/zaloguj")
    end
  end

  # Like a sign-in, a change of identity renews the session and its CSRF token.
  defp sign_in(conn, user, token) do
    delete_csrf_token()

    conn
    |> Helpers.store_in_session(Ash.Resource.put_metadata(user, :token, token))
    |> AuthenticationController.set_live_socket_id(token)
  end
end
