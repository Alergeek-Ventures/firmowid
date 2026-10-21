defmodule Firmowid.Ash.Core.UserTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  describe "member archive authorization" do
    test "an admin cannot archive or restore another organization's member" do
      admin = admin_fixture()
      outsider = user_fixture()
      opts = [actor: admin, tenant: outsider.organization_id]

      assert {:error, _} = Core.archive_member(outsider.member, opts)
      archived = Ash.Seed.update!(outsider.member, %{archived_at: Date.utc_today()})
      assert {:error, _} = Core.unarchive_member(archived, opts)
    end

    test "employees cannot archive colleagues and admins cannot archive themselves" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.organization_id)
      colleague = user_in_org_fixture(admin.organization_id)

      assert {:error, _} =
               Core.archive_member(colleague.member,
                 scope: Scope.new!(employee, admin.organization_id)
               )

      assert {:error, _} =
               Core.archive_member(admin.member, scope: Scope.new!(admin, admin.organization_id))
    end
  end

  describe "member profile authorization" do
    test "an employee updates their own profile details but not a colleague's" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.organization_id)
      colleague = user_in_org_fixture(admin.organization_id)
      scope = Scope.new!(employee, admin.organization_id)

      assert {:ok, %{phone: "+48 600 100 200"}} =
               Core.update_member_profile(employee.member, %{phone: "+48 600 100 200"}, scope: scope)

      assert {:error, _} =
               Core.update_member_profile(colleague.member, %{phone: "+48 600 100 200"}, scope: scope)

      assert Core.load_member(colleague, admin.organization_id).member.phone == nil
    end

    test "only the member, their admin and account readers see profile details" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.organization_id)
      coworker = user_in_org_fixture(admin.organization_id)
      outsider = admin_fixture()
      tenant = admin.organization_id

      Core.update_member_profile!(
        employee.member,
        %{phone: "+48 600 100 200", birthday: ~D[1990-05-01]},
        scope: Scope.new!(employee, tenant)
      )

      read = fn opts ->
        opts
        |> Keyword.put(:load, [:shared_birthday])
        |> Member.list!()
        |> Enum.find(&(&1.id == employee.member.id))
      end

      assert %{phone: "+48 600 100 200", birthday: ~D[1990-05-01]} =
               read.(actor: admin, tenant: tenant)

      assert read.(actor: coworker, tenant: tenant) == nil
      assert read.(actor: outsider, tenant: tenant) == nil

      analysis =
        read.(actor: %SystemActor{org_id: tenant, role: :analysis_reader}, tenant: tenant)

      assert analysis.user_id == employee.id
      assert %Ash.ForbiddenField{} = analysis.phone
      assert %Ash.ForbiddenField{} = analysis.birthday
      assert %Ash.ForbiddenField{} = analysis.shared_birthday
    end

    test "another organization's admin cannot update a member's profile details" do
      employee = user_fixture()
      outsider = admin_fixture()

      assert {:error, _} =
               Core.update_member_profile(employee.member, %{phone: "+48 600 100 200"},
                 actor: outsider,
                 tenant: employee.organization_id
               )

      assert Core.load_member(employee, employee.organization_id).member.phone == nil
    end
  end

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
      assert updated.member.phone == "+48123456789"

      assert Core.get_user!(employee.id, actor: employee).name != "Ada Lovelace"
    end

    test "keeps the name when the profile details are invalid" do
      user = user_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}
      user = Core.update_profile!(user, %{name: "Ada Lovelace"}, scope: scope)

      assert {:error, _} =
               Core.update_current_profile(
                 %{name: "Grace Hopper", bank_account_number: "PL00 123"},
                 scope: scope
               )

      assert Core.get_user!(user.id, actor: user).name == "Ada Lovelace"
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
