defmodule Firmowid.Ash.Core.UserTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs.Blob
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
        |> Keyword.put(:load, [:shared_birthday, :display_name])
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
      assert %Ash.ForbiddenField{} = analysis.name
      assert %Ash.ForbiddenField{} = analysis.display_name
      assert %Ash.ForbiddenField{} = analysis.avatar_blob_id
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

    test "another organization's admin cannot read or change a member's name and avatar" do
      employee = user_fixture()
      outsider = admin_fixture()
      tenant = employee.organization_id
      opts = [actor: outsider, tenant: tenant]

      blob =
        Ash.Seed.seed!(Blob, %{
          organization_id: tenant,
          blob_path: "#{tenant}/avatar.png",
          blob_checksum: "avatar",
          original_filename: "avatar.png"
        })

      Core.update_member_profile!(employee.member, %{name: "Ada Lovelace"}, scope: Scope.new!(employee, tenant))

      assert Member.list!(opts) == []

      assert {:error, _} =
               Core.update_member_profile(employee.member, %{name: "Grace Hopper"}, opts)

      assert {:error, _} =
               Core.update_member_avatar(employee.member, %{avatar_blob_id: blob.id}, opts)

      assert %{name: "Ada Lovelace", avatar_blob_id: nil} =
               Core.load_member(employee, tenant).member
    end

    test "a member cannot use another organization's blob as their avatar" do
      employee = user_fixture()
      other_organization_id = admin_fixture().organization_id

      blob =
        Ash.Seed.seed!(Blob, %{
          organization_id: other_organization_id,
          blob_path: "#{other_organization_id}/avatar.png",
          blob_checksum: "foreign-avatar",
          original_filename: "avatar.png"
        })

      assert {:error, %Ash.Error.Invalid{}} =
               Core.update_member_avatar(employee.member, %{avatar_blob_id: blob.id},
                 scope: Scope.new!(employee, employee.organization_id)
               )

      assert Core.load_member(employee, employee.organization_id).member.avatar_blob_id == nil
    end
  end

  describe "display_name" do
    test "uses the member's name when present and otherwise falls back to the email" do
      named_user = user_fixture()
      unnamed_user = user_in_org_fixture(named_user.organization_id)
      named_scope = %Scope{actor: named_user, tenant: named_user.organization_id}

      named_member =
        named_user.member
        |> Core.update_member_profile!(%{name: "Ada Lovelace"}, scope: named_scope)
        |> Ash.load!(:display_name, scope: named_scope)

      unnamed_member =
        Ash.load!(unnamed_user.member, :display_name,
          scope: %Scope{actor: unnamed_user, tenant: unnamed_user.organization_id}
        )

      assert named_member.display_name == "Ada Lovelace"
      assert unnamed_member.display_name == to_string(unnamed_user.email)
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
      assert updated.member.name == "Ada Lovelace"
      assert updated.member.phone == "+48123456789"

      assert Core.load_member(employee, admin.organization_id).member.name != "Ada Lovelace"
    end

    test "keeps the name when the profile details are invalid" do
      user = user_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}
      member = Core.update_member_profile!(user.member, %{name: "Ada Lovelace"}, scope: scope)
      scope = %{scope | actor: %{user | member: member}}

      assert {:error, _} =
               Core.update_current_profile(
                 %{name: "Grace Hopper", bank_account_number: "PL00 123"},
                 scope: scope
               )

      assert Core.load_member(user, user.organization_id).member.name == "Ada Lovelace"
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
