defmodule Firmowid.Ash.Core.Changes.CleanupOldAvatarBlobTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Scope

  describe "cleanup_old_avatar_blob" do
    test "replacing an employee avatar preserves another member's reference to the same blob" do
      user = user_fixture(%{role: :employee})
      other = user_in_org_fixture(user.member.organization_id, %{role: :employee})
      scope = %Scope{actor: user, tenant: user.member.organization_id}
      other_scope = %Scope{actor: other, tenant: other.member.organization_id}
      image = File.read!("priv/static/images/favicon.png")
      shared_blob = create_blob!(scope, image, "shared-avatar.png", "image/png")

      assert {:ok, member} =
               Core.update_member_avatar(user.member, %{avatar_blob_id: shared_blob.id}, scope: scope)

      assert {:ok, _other_member} =
               Core.update_member_avatar(other.member, %{avatar_blob_id: shared_blob.id}, scope: other_scope)

      replacement = create_blob!(scope, "replacement avatar", "replacement.txt")

      assert {:ok, _member} =
               Core.update_member_avatar(member, %{avatar_blob_id: replacement.id}, scope: scope)

      assert [%{avatar_blob_id: avatar_blob_id}] = Member.list!(scope: other_scope)
      assert avatar_blob_id == shared_blob.id
      assert Blobs.get_blob!(shared_blob.id, scope: other_scope).id == shared_blob.id
    end

    test "replacing an avatar that reused a pending document blob keeps the document" do
      admin = user_fixture(%{role: :admin})
      employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})
      admin_scope = %Scope{actor: admin, tenant: admin.member.organization_id}
      scope = %Scope{actor: employee, tenant: employee.member.organization_id}
      {:ok, path} = Briefly.create()
      File.write!(path, "%PDF-1.4 employment contract")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, document} =
                 Blobs.create_blob_for_processing(
                   path,
                   "application/pdf",
                   "contract.pdf",
                   :employment_contract,
                   %{member_id: employee.member.id},
                   scope: admin_scope
                 )

        # Avatar upload trusts the client MIME type, so the same bytes reuse the document blob.
        assert {:ok, %{id: document_id}} =
                 Blobs.create_or_reuse_blob(path, "application/pdf", "avatar.png", scope: scope)

        assert document_id == document.id

        assert {:ok, member} =
                 Core.update_member_avatar(employee.member, %{avatar_blob_id: document.id}, scope: scope)

        replacement = create_blob!(scope, "replacement avatar", "replacement.txt")

        assert {:ok, _member} =
                 Core.update_member_avatar(member, %{avatar_blob_id: replacement.id}, scope: scope)

        assert %{processing_state: :pending} = Blobs.get_blob!(document.id, scope: admin_scope)
      end)
    end

    test "non-admin replace avatar and destroys the previous unreferenced blob" do
      # Explicit non-admin: admins bypass Blob.destroy and would not catch this.
      user = user_fixture(%{role: :employee})
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      first_blob = create_blob!(scope, "first avatar", "avatar-1.txt")

      assert {:ok, member} =
               Core.update_member_avatar(user.member, %{avatar_blob_id: first_blob.id}, scope: scope)

      assert member.avatar_blob_id == first_blob.id

      second_blob = create_blob!(scope, "second avatar", "avatar-2.txt")

      assert {:ok, updated_member} =
               Core.update_member_avatar(member, %{avatar_blob_id: second_blob.id}, scope: scope)

      assert updated_member.avatar_blob_id == second_blob.id

      assert_raise Ash.Error.Invalid, fn ->
        Blobs.get_blob!(first_blob.id, scope: scope)
      end

      assert Blobs.get_blob!(second_blob.id, scope: scope).id == second_blob.id
    end
  end

  defp create_blob!(scope, content, filename, content_type \\ "text/plain") do
    {:ok, path} = Briefly.create()
    File.write!(path, content)

    assert {:ok, blob} = Blobs.create_blob(path, content_type, filename, scope: scope)
    blob
  end
end
