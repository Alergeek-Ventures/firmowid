defmodule FirmowidWeb.Organization.Controllers.Switch do
  @moduledoc """
  Switches the organization the user works in.

  The selected organization is stored in the session only after checking that the
  user has a usable member there. Other open tabs keep their organization until
  they load a page again: a LiveView reads the session when its socket connects.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Core
  alias FirmowidWeb.Auth.Utilities.PendingAuthorization
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation

  @doc """
  Selects the organization given in the `organizacja` param. With `cel` set to
  the first steps, a just created organization continues with its setup.
  """
  @spec switch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def switch(conn, %{"organizacja" => organization_id} = params) do
    user = conn.assigns.current_user

    if Enum.any?(
         conn.assigns.organizations,
         &(&1.id == organization_id and Core.usable_organization?(user, &1))
       ) do
      conn
      |> put_session(UserAuth.organization_session_key(), organization_id)
      |> redirect(to: destination(conn, params["cel"], user, organization_id))
    else
      conn
      |> LiveToast.put_toast(:error, gettext("You do not belong to this organization."))
      |> redirect(to: UserAuth.signed_in_path(conn))
    end
  end

  # A company that is ready right away goes back to the AI client waiting for it, if any.
  defp destination(conn, target, user, organization_id) do
    cond do
      target == OrganizationNavigation.first_steps_target() ->
        OrganizationNavigation.first_steps_path()

      path = PendingAuthorization.return_path(conn) ->
        path

      true ->
        UserAuth.signed_in_path_for_user(user, organization_id)
    end
  end
end
