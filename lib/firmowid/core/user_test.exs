defmodule Firmowid.Core.UserTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Core.Member
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  describe "member archive authorization" do
    test "an admin cannot archive or restore another organization's member" do
      admin = admin_fixture()
      outsider = user_fixture()
      opts = [actor: admin, tenant: outsider.member.organization_id]

      assert {:error, _} = Core.archive_member(outsider.member, opts)
      archived = Ash.Seed.update!(outsider.member, %{archived_at: Date.utc_today()})
      assert {:error, _} = Core.unarchive_member(archived, opts)
    end

    test "employees cannot archive colleagues and admins cannot archive themselves" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.member.organization_id)
      colleague = user_in_org_fixture(admin.member.organization_id)

      assert {:error, _} =
               Core.archive_member(colleague.member,
                 scope: Scope.new!(employee, admin.member.organization_id)
               )

      assert {:error, _} =
               Core.archive_member(admin.member,
                 scope: Scope.new!(admin, admin.member.organization_id)
               )
    end
  end

  describe "member profile authorization" do
    test "an employee updates their own profile details but not a colleague's" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.member.organization_id)
      colleague = user_in_org_fixture(admin.member.organization_id)
      scope = Scope.new!(employee, admin.member.organization_id)

      assert {:ok, %{phone: "+48 600 100 200"}} =
               Core.update_member_profile(employee.member, %{phone: "+48 600 100 200"}, scope: scope)

      assert {:error, _} =
               Core.update_member_profile(colleague.member, %{phone: "+48 600 100 200"}, scope: scope)

      assert Core.load_member(colleague).member.phone == nil
    end

    test "only the member, their admin and account readers see profile details" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.member.organization_id)
      coworker = user_in_org_fixture(admin.member.organization_id)
      outsider = admin_fixture()
      tenant = admin.member.organization_id

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
                 tenant: employee.member.organization_id
               )

      assert Core.load_member(employee).member.phone == nil
    end

    test "another organization's admin cannot read or change a member's name and avatar" do
      employee = user_fixture()
      outsider = admin_fixture()
      tenant = employee.member.organization_id
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
               Core.load_member(employee).member
    end

    test "a member cannot use another organization's blob as their avatar" do
      employee = user_fixture()
      other_organization_id = admin_fixture().member.organization_id

      blob =
        Ash.Seed.seed!(Blob, %{
          organization_id: other_organization_id,
          blob_path: "#{other_organization_id}/avatar.png",
          blob_checksum: "foreign-avatar",
          original_filename: "avatar.png"
        })

      assert {:error, %Invalid{}} =
               Core.update_member_avatar(employee.member, %{avatar_blob_id: blob.id},
                 scope: Scope.new!(employee, employee.member.organization_id)
               )

      assert Core.load_member(employee).member.avatar_blob_id == nil
    end
  end

  test "an organization admin cannot delete a member's account" do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)

    assert {:error, %Ash.Error.Forbidden.Policy{}} =
             Core.destroy_user(employee, scope: Scope.new!(admin, admin.member.organization_id))

    assert {:ok, _} = Core.get_user(employee.id, authorize?: false)
  end

  describe "closing the account" do
    test "its holder may delete it, a superuser working as the holder may not" do
      user = user_fixture()

      as_superuser =
        Ash.Resource.put_metadata(user, :token_claims, %{"impersonator_id" => Ash.UUID.generate()})

      assert Ash.can?({user, :destroy}, user)
      refute Ash.can?({user, :destroy}, as_superuser)
    end
  end

  describe "display_name" do
    test "uses the member's name when present and otherwise falls back to the email" do
      named_user = user_fixture()
      unnamed_user = user_in_org_fixture(named_user.member.organization_id)
      named_scope = %Scope{actor: named_user, tenant: named_user.member.organization_id}

      named_member =
        named_user.member
        |> Core.update_member_profile!(%{name: "Ada Lovelace"}, scope: named_scope)
        |> Ash.load!(:display_name, scope: named_scope)

      unnamed_member =
        Ash.load!(unnamed_user.member, :display_name,
          scope: %Scope{actor: unnamed_user, tenant: unnamed_user.member.organization_id}
        )

      assert named_member.display_name == "Ada Lovelace"
      assert unnamed_member.display_name == to_string(unnamed_user.email)
    end
  end

  describe "update_current_profile/2" do
    test "updates only the acting user's profile" do
      admin = admin_fixture()
      employee = user_in_org_fixture(admin.member.organization_id)
      scope = %Scope{actor: admin, tenant: admin.member.organization_id}

      assert {:ok, updated} =
               Core.update_current_profile(
                 %{name: "Ada Lovelace", phone: "+48123456789"},
                 scope: scope
               )

      assert updated.id == admin.id
      assert updated.member.name == "Ada Lovelace"
      assert updated.member.phone == "+48123456789"

      assert Core.load_member(employee).member.name != "Ada Lovelace"
    end

    test "stores an account number typed as 26 digits with the PL prefix" do
      user = user_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      assert {:ok, updated} =
               Core.update_current_profile(
                 %{bank_account_number: " 23 1140 2004 0000 3002 0135 5362 "},
                 scope: scope
               )

      assert updated.member.bank_account_number == "PL23 1140 2004 0000 3002 0135 5362"
    end

    test "refuses an account number with a wrong checksum with the validation message" do
      user = user_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      assert {:error, error} =
               Core.update_current_profile(%{bank_account_number: "23114020040000300201355363"},
                 scope: scope
               )

      assert Exception.message(error) =~ "must be a valid bank account number (IBAN)"
      assert Core.load_member(user).member.bank_account_number == nil
    end

    test "keeps the name when the profile details are invalid" do
      user = user_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}
      member = Core.update_member_profile!(user.member, %{name: "Ada Lovelace"}, scope: scope)
      scope = %{scope | actor: %{user | member: member}}

      assert {:error, _} =
               Core.update_current_profile(
                 %{name: "Grace Hopper", bank_account_number: "PL00 123"},
                 scope: scope
               )

      assert Core.load_member(user).member.name == "Ada Lovelace"
    end
  end

  test "exposes the self-scoped profile update tool" do
    assert :update_profile in (Core |> AshAi.Info.tools() |> Enum.map(& &1.name))
  end

  test "a user cannot assign themselves to another organization" do
    user = user_fixture()
    other_user = user_fixture()

    assert {:error, _} =
             Core.set_organization(user, %{organization_id: other_user.member.organization_id},
               scope: %Scope{actor: user, tenant: user.member.organization_id}
             )
  end

  test "the organization setup actor only reads and assigns its own user" do
    user = user_fixture()
    other_user = user_fixture()
    organization_id = user.member.organization_id

    actor = %SystemActor{
      org_id: organization_id,
      role: :organization_owner_setup,
      user_id: user.id
    }

    assert Ash.can?(
             {user, :set_organization, %{organization_id: organization_id, role: :admin}},
             actor
           )

    refute Ash.can?(
             {other_user, :set_organization, %{organization_id: organization_id, role: :admin}},
             actor
           )

    refute Ash.can?(
             {user, :set_organization, %{organization_id: other_user.member.organization_id, role: :admin}},
             actor
           )

    refute Ash.can?({user, :destroy}, actor)

    assert {:error, %Forbidden{}} =
             Member.create(%{user_id: other_user.id, role: :admin},
               actor: actor,
               tenant: organization_id
             )
  end

  test "notifier system actors read only users of their organization" do
    user = user_fixture()
    outsider = user_fixture()
    organization_id = user.member.organization_id

    for role <- [
          :leave_notifier,
          :delegation_notifier,
          :hours_record_change_notifier,
          :document_blob_processor,
          :employment_contract_notifier
        ] do
      actor = %SystemActor{org_id: organization_id, role: role}

      assert {:ok, _} = Core.get_user(user.id, actor: actor)
      assert {:error, _} = Core.get_user(outsider.id, actor: actor)
    end
  end

  test "an organization admin revokes a member's access only to their own organization" do
    admin = admin_fixture()
    other_organization_id = admin_fixture().member.organization_id
    employee = user_in_org_fixture(admin.member.organization_id)
    Core.add_to_organization!(employee.id, other_organization_id, :employee, nil)
    scope = Scope.new!(admin, admin.member.organization_id)

    assert {:error, %Forbidden{}} =
             Core.leave_organization(employee, other_organization_id, scope: scope)

    assert {:ok, _} =
             Core.leave_organization(employee, admin.member.organization_id, scope: scope)
  end
end
