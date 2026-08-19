defmodule FirmowidWeb.Mcp.Utilities.AuthenticateTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias FirmowidWeb.Mcp.Utilities.Authenticate

  test "rejects requests without an authenticated actor", %{conn: conn} do
    conn = Authenticate.call(conn, [])

    assert conn.halted
    assert conn.status == 401
  end

  test "rejects authenticated users without an organization", %{conn: conn} do
    user =
      Firmowid.Ash.Core.register_with_password!(
        %{email: unique_user_email(), password: valid_user_password()},
        authorize?: false,
        actor: %{}
      )

    conn =
      conn
      |> Ash.PlugHelpers.set_actor(user)
      |> Authenticate.call([])

    assert conn.halted
    assert conn.status == 401
  end

  test "uses the authenticated user's organization as the Ash tenant", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> Ash.PlugHelpers.set_actor(user)
      |> Authenticate.call([])

    refute conn.halted
    assert Ash.PlugHelpers.get_actor(conn).id == user.id
    assert Ash.PlugHelpers.get_tenant(conn) == user.organization_id
  end
end
