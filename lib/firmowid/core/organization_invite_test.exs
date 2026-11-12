defmodule Firmowid.Core.OrganizationInviteTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Core

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
end
