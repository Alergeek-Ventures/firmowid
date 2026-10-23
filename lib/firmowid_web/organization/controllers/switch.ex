defmodule FirmowidWeb.Organization.Controllers.Switch do
  @moduledoc """
  Switches the organization the user works in.

  The selected organization is stored in the session only after checking that the
  user has a usable member there. Other open tabs keep their organization until
  they load a page again: a LiveView reads the session when its socket connects.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Core
  alias FirmowidWeb.Infrastructure.UserAuth

  @doc "Selects the organization given in the `organizacja` param."
  @spec switch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def switch(conn, %{"organizacja" => organization_id}) do
    user = conn.assigns.current_user

    if Enum.any?(
         conn.assigns.organizations,
         &(&1.id == organization_id and Core.usable_organization?(user, &1))
       ) do
      conn
      |> put_session(UserAuth.organization_session_key(), organization_id)
      |> redirect(to: UserAuth.signed_in_path_for_user(user, organization_id))
    else
      conn
      |> LiveToast.put_toast(:error, "Nie należysz do tej organizacji.")
      |> redirect(to: UserAuth.signed_in_path(conn))
    end
  end
end
