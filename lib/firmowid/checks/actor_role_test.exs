defmodule Firmowid.Checks.ActorRoleTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Core
  alias Firmowid.Finances.Requisition

  describe "a member's role outside their organization" do
    test "does not count in another organization's tenant" do
      admin = admin_fixture()
      other_admin = admin_fixture()
      other_tenant = other_admin.member.organization_id

      Core.create_invite!(%{issued_by_id: other_admin.id},
        actor: other_admin,
        tenant: other_tenant
      )

      assert [] = Core.list_invites!(actor: admin, tenant: other_tenant)
    end

    test "does not count without a tenant on a multitenant resource" do
      admin = admin_fixture()
      other_tenant = admin_fixture().member.organization_id
      Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate()}, tenant: other_tenant)

      assert {:ok, %{results: []}} = Requisition.read_global(actor: admin, page: [limit: 10])
    end
  end
end
