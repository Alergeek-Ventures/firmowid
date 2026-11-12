defmodule Firmowid.Checks.SystemActorRoleTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Finances
  alias Firmowid.Finances.Requisition
  alias Firmowid.SystemActor

  test "a system actor built for one organization holds its role only in that tenant" do
    tenant = admin_fixture().member.organization_id
    other_tenant = admin_fixture().member.organization_id
    requisition = Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate()}, tenant: tenant)
    actor = %SystemActor{org_id: tenant, role: :bank_sync}

    assert {:ok, [%{id: id}]} = Finances.list_requisitions(actor: actor, tenant: tenant)
    assert id == requisition.id

    assert {:ok, []} =
             Finances.list_requisitions(actor: %{actor | org_id: other_tenant}, tenant: tenant)
  end
end
