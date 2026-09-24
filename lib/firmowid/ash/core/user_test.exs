defmodule Firmowid.Ash.Core.UserTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope

  describe "display_name" do
    test "uses the name when present and otherwise falls back to the email" do
      named_user = user_fixture()
      unnamed_user = user_fixture(%{name: nil})

      named_user =
        Core.update_profile!(named_user, %{name: "Ada Lovelace"},
          actor: named_user,
          tenant: named_user.organization_id
        )

      named_user =
        Ash.load!(named_user, :display_name, scope: %Scope{actor: named_user, tenant: named_user.organization_id})

      unnamed_user =
        Ash.load!(unnamed_user, :display_name, scope: %Scope{actor: unnamed_user, tenant: unnamed_user.organization_id})

      assert named_user.display_name == "Ada Lovelace"
      assert unnamed_user.display_name == to_string(unnamed_user.email)
    end
  end

  describe "update_current_profile/2" do
    test "updates only the acting user's profile" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.organization_id)
      scope = %Scope{actor: admin, tenant: admin.organization_id}

      assert {:ok, updated} =
               Core.update_current_profile(
                 %{name: "Ada Lovelace", phone: "+48123456789"},
                 scope: scope
               )

      assert updated.id == admin.id
      assert updated.name == "Ada Lovelace"
      assert updated.phone == "+48123456789"

      assert Core.get_user!(employee.id, actor: employee).name != "Ada Lovelace"
    end
  end

  test "exposes the self-scoped profile update tool" do
    assert :update_profile in (Core |> AshAi.Info.tools() |> Enum.map(& &1.name))
  end

  test "a user cannot assign themselves to another organization" do
    user = user_fixture()
    other_user = user_fixture()

    assert {:error, _} =
             Core.set_organization(user, %{organization_id: other_user.organization_id},
               scope: %Scope{actor: user, tenant: user.organization_id}
             )
  end
end
