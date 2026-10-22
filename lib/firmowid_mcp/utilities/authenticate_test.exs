defmodule FirmowidMcp.Utilities.AuthenticateTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Core
  alias FirmowidMcp.Utilities.Authenticate

  test "rejects requests without an authenticated actor", %{conn: conn} do
    conn = Authenticate.call(conn, [])

    assert conn.halted
    assert conn.status == 401
  end

  test "rejects authenticated users without an organization", %{conn: conn} do
    user =
      Core.register_with_password!(
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
    assert Ash.PlugHelpers.get_tenant(conn) == user.member.organization_id
  end

  test "uses the active member's organization, not one the user was archived from", %{conn: conn} do
    admin = admin_fixture()
    user = user_in_org_fixture(admin.member.organization_id)
    Core.archive_member!(user.member, actor: admin, tenant: admin.member.organization_id)

    other_organization_id = admin_fixture().member.organization_id

    Core.set_organization!(user, %{organization_id: other_organization_id, role: :employee}, authorize?: false)

    conn =
      conn
      |> Ash.PlugHelpers.set_actor(user)
      |> Authenticate.call([])

    refute conn.halted
    assert Ash.PlugHelpers.get_tenant(conn) == other_organization_id
    assert Ash.PlugHelpers.get_actor(conn).member.organization_id == other_organization_id
  end

  test "authenticates a user with several organizations in the default one", %{conn: conn} do
    user = user_fixture()

    organization =
      Core.create_organization!(%{nip: unique_nip(), name: "Druga firma", owner_name: "Druga"},
        actor: user
      )

    conn =
      conn
      |> Ash.PlugHelpers.set_actor(user)
      |> Authenticate.call([])

    refute conn.halted
    assert Ash.PlugHelpers.get_tenant(conn) == organization.id
    assert Ash.PlugHelpers.get_actor(conn).member.organization_id == organization.id
  end
end
