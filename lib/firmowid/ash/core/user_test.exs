defmodule Firmowid.Ash.Core.UserTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope

  describe "update_current_profile/2" do
    test "updates only the acting user's profile" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.organization_id)
      scope = %Scope{actor: admin, tenant: admin.organization_id}

      assert {:ok, updated} =
               Core.update_current_profile(
                 %{name: "Ada Lovelace", position: "Engineer", phone: "+48123456789"},
                 scope: scope
               )

      assert updated.id == admin.id
      assert updated.name == "Ada Lovelace"
      assert updated.position == "Engineer"
      assert updated.phone == "+48123456789"

      assert Core.get_user!(employee.id, actor: employee).name != "Ada Lovelace"
    end
  end

  test "exposes the self-scoped profile update tool" do
    assert :update_profile in (Core |> AshAi.Info.tools() |> Enum.map(& &1.name))
  end
end
