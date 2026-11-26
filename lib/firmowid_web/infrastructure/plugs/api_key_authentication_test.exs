defmodule FirmowidWeb.Infrastructure.Plugs.ApiKeyAuthenticationTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Core
  alias Firmowid.Core.ServiceAccount
  alias FirmowidWeb.Infrastructure.Plugs.ApiKeyAuthentication

  defp authenticate(conn, authorization) do
    conn =
      if authorization, do: put_req_header(conn, "authorization", authorization), else: conn

    ApiKeyAuthentication.call(conn, [])
  end

  defp bearer(key), do: "Bearer " <> key.__metadata__.plaintext_api_key

  defp personal_key(user, attrs \\ %{}) do
    Core.create_api_key!(Map.merge(%{name: "Skrypt"}, attrs),
      actor: user,
      tenant: user.member.organization_id
    )
  end

  defp company_key(admin) do
    Core.create_company_api_key!(%{name: "Sklep", role: :accountant},
      actor: admin,
      tenant: admin.member.organization_id
    )
  end

  defp assert_unauthorized(conn) do
    assert conn.halted

    assert json_response(conn, 401) == %{
             "error" => "unauthorized",
             "message" => "A valid API key is required"
           }
  end

  test "a personal key acts as its member, in the key's organization", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    key = personal_key(admin)

    # The newer organization becomes the account's default one.
    Core.create_organization!(%{nip: unique_nip(), name: "Druga firma", owner_name: "Druga"},
      actor: admin
    )

    conn = authenticate(conn, bearer(key))

    refute conn.halted
    actor = Ash.PlugHelpers.get_actor(conn)
    assert actor.id == admin.id
    assert actor.member.organization_id == organization_id
    assert actor.__metadata__.using_api_key?
    assert Ash.PlugHelpers.get_tenant(conn) == organization_id
  end

  test "a company key acts as its account and outlives the admin who created it", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    creator = user_in_org_fixture(organization_id, %{role: :admin})
    key = company_key(creator)

    Core.archive_member!(creator.member, actor: admin, tenant: organization_id)

    conn = authenticate(conn, bearer(key))

    refute conn.halted

    assert %ServiceAccount{role: :accountant, organization_id: ^organization_id} =
             Ash.PlugHelpers.get_actor(conn)

    assert Ash.PlugHelpers.get_tenant(conn) == organization_id
  end

  test "rejects a request without a valid key", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    personal = personal_key(admin)
    company = company_key(admin)

    assert_unauthorized(authenticate(conn, nil))
    # The key's ID with a wrong secret.
    assert_unauthorized(authenticate(conn, bearer(personal) <> "0"))

    for key <- [personal, company] do
      Core.revoke_api_key!(key, actor: admin, tenant: organization_id)
      assert_unauthorized(authenticate(conn, bearer(key)))
    end
  end

  test "rejects an expired key", %{conn: conn} do
    admin = admin_fixture()
    key = personal_key(admin, %{expires_on: Date.add(Firmowid.LocalDate.today(), 1)})

    Ash.Seed.update!(key, %{expires_at: DateTime.shift(DateTime.utc_now(), minute: -1)})

    assert_unauthorized(authenticate(conn, bearer(key)))
  end

  test "revokes the personal keys of a member who leaves the organization", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    leaving = user_in_org_fixture(organization_id)
    key = personal_key(leaving)

    Core.archive_member!(leaving.member, actor: admin, tenant: organization_id)

    assert_unauthorized(authenticate(conn, bearer(key)))
    assert Core.list_api_keys!(actor: admin, tenant: organization_id) == []
  end

  test "rejects the keys of an organization without a billing plan", %{conn: conn} do
    admin = admin_fixture()
    keys = [personal_key(admin), company_key(admin)]

    admin.member.organization_id
    |> Core.get_organization!(authorize?: false)
    |> Core.update_organization_billing_plan!(%{billing_plan: :no_plan}, authorize?: false)

    for key <- keys, do: assert_unauthorized(authenticate(conn, bearer(key)))
  end
end
