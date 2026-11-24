defmodule FirmowidWeb.Infrastructure.Plugs.ApiKeyOrganizationTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias AshAuthentication.Strategy.ApiKey
  alias Firmowid.Core
  alias FirmowidWeb.Infrastructure.Plugs.ApiKeyOrganization

  # The `:api_key` pipeline of the router.
  defp authenticate(conn, authorization) do
    api_key_plug =
      ApiKey.Plug.init(resource: Core.User, on_error: &ApiKeyOrganization.unauthorized/2)

    conn =
      if authorization, do: put_req_header(conn, "authorization", authorization), else: conn

    case ApiKey.Plug.call(conn, api_key_plug) do
      %{halted: true} = conn -> conn
      conn -> ApiKeyOrganization.call(conn, [])
    end
  end

  defp create_key(admin, attrs \\ %{}) do
    key =
      Core.create_api_key!(Map.merge(%{name: "Sklep", scopes: [:sales_invoices]}, attrs),
        actor: admin,
        tenant: admin.member.organization_id
      )

    {key, "Bearer " <> key.__metadata__.plaintext_api_key}
  end

  defp assert_unauthorized(conn) do
    assert conn.halted

    assert json_response(conn, 401) == %{
             "error" => "unauthorized",
             "message" => "A valid API key is required"
           }
  end

  test "acts as the admin who created the key, in the key's organization", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    {_key, authorization} = create_key(admin)

    # The newer organization becomes the account's default one.
    Core.create_organization!(%{nip: unique_nip(), name: "Druga firma", owner_name: "Druga"},
      actor: admin
    )

    conn = authenticate(conn, authorization)

    refute conn.halted
    actor = Ash.PlugHelpers.get_actor(conn)
    assert actor.id == admin.id
    assert actor.member.organization_id == organization_id
    assert actor.__metadata__.using_api_key?
    assert actor.__metadata__.api_key.scopes == [:sales_invoices]
    assert Ash.PlugHelpers.get_tenant(conn) == organization_id
  end

  test "rejects a request without a valid key", %{conn: conn} do
    admin = admin_fixture()
    {key, authorization} = create_key(admin)

    assert_unauthorized(authenticate(conn, nil))
    # The key's ID with a wrong secret.
    assert_unauthorized(authenticate(conn, authorization <> "0"))

    Core.revoke_api_key!(key, actor: admin, tenant: admin.member.organization_id)
    assert_unauthorized(authenticate(conn, authorization))
  end

  test "rejects an expired key", %{conn: conn} do
    {_key, authorization} =
      create_key(admin_fixture(), %{expires_at: DateTime.shift(DateTime.utc_now(), minute: -1)})

    assert_unauthorized(authenticate(conn, authorization))
  end

  test "revokes the keys of a member who leaves the organization", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    leaving = user_in_org_fixture(organization_id, %{role: :admin})
    {_key, authorization} = create_key(leaving)

    Core.archive_member!(leaving.member, actor: admin, tenant: organization_id)

    assert_unauthorized(authenticate(conn, authorization))
    assert Core.list_api_keys!(actor: admin, tenant: organization_id) == []
  end

  test "works only while the key's admin is still an admin", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    demoted = user_in_org_fixture(organization_id, %{role: :admin})
    {_key, authorization} = create_key(demoted)

    member =
      Core.update_member_role!(demoted.member, %{role: :accountant},
        actor: admin,
        tenant: organization_id
      )

    assert_unauthorized(authenticate(conn, authorization))

    Core.update_member_role!(member, %{role: :admin}, actor: admin, tenant: organization_id)
    refute authenticate(conn, authorization).halted
  end

  test "rejects a key of an organization without a billing plan", %{conn: conn} do
    admin = admin_fixture()
    {_key, authorization} = create_key(admin)

    admin.member.organization_id
    |> Core.get_organization!(authorize?: false)
    |> Core.update_organization_billing_plan!(%{billing_plan: :no_plan}, authorize?: false)

    assert_unauthorized(authenticate(conn, authorization))
  end
end
