defmodule Firmowid.Core.OrganizationInviteTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Core
  alias Firmowid.SystemActor

  test "an expired invite cannot be consumed" do
    admin = admin_fixture()
    tenant = admin.member.organization_id
    invite = Core.create_invite!(%{issued_by_id: admin.id}, actor: admin, tenant: tenant)

    expired =
      Ash.Seed.update!(invite, %{expires_at: DateTime.shift(DateTime.utc_now(), second: -1)})

    user = Core.load_member(user_fixture())

    assert {:error, _} =
             Core.consume_invite(expired, %{name: "Jan Kowalski"}, actor: user, tenant: tenant)

    assert [] = user |> Core.list_active_members() |> Enum.filter(&(&1.organization_id == tenant))
  end

  test "archiving a member revokes the codes they hold; a new invite restores them" do
    owner = admin_fixture()
    tenant = owner.member.organization_id
    admin = user_in_org_fixture(tenant, %{role: :admin})

    own_invite =
      Core.create_invite!(%{issued_by_id: admin.id, role: :admin}, actor: admin, tenant: tenant)

    owner_invite = Core.create_invite!(%{issued_by_id: owner.id}, actor: owner, tenant: tenant)

    Core.archive_member!(admin.member, actor: owner, tenant: tenant)
    archived = Core.load_member(admin)

    for invite <- [own_invite, owner_invite] do
      assert {:ok, []} =
               Core.read_invite_by_code(%{invite_code: invite.invite_code}, actor: archived)

      assert {:error, _} =
               Core.consume_invite(invite, %{name: "Jan Kowalski"},
                 actor: archived,
                 tenant: tenant
               )
    end

    assert [] = active_members(archived, tenant)

    new_invite = Core.create_invite!(%{issued_by_id: owner.id}, actor: owner, tenant: tenant)

    assert {:ok, _} =
             Core.consume_invite(new_invite, %{name: "Jan Kowalski"},
               actor: archived,
               tenant: tenant
             )

    assert [%{role: :employee}] = active_members(archived, tenant)
  end

  test "the plan limit's archival revokes the pending invites too" do
    owner = admin_fixture()
    tenant = owner.member.organization_id
    employee = user_in_org_fixture(tenant)
    invite = Core.create_invite!(%{issued_by_id: owner.id}, actor: owner, tenant: tenant)
    plan_limits = %SystemActor{org_id: tenant, role: :plan_limits}

    Core.archive_member!(employee.member, %{by_plan?: true}, actor: plan_limits, tenant: tenant)

    assert {:ok, []} =
             Core.read_invite_by_code(%{invite_code: invite.invite_code}, actor: employee)
  end

  defp active_members(user, organization_id) do
    user |> Core.list_active_members() |> Enum.filter(&(&1.organization_id == organization_id))
  end
end
