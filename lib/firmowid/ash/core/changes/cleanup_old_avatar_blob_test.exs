defmodule Firmowid.Ash.Core.Changes.CleanupOldAvatarBlobTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope

  describe "cleanup_old_avatar_blob" do
    test "non-admin replace avatar and destroys the previous unreferenced blob" do
      # Explicit non-admin: admins bypass Blob.destroy and would not catch this.
      user = user_fixture(%{role: :employee})
      scope = %Scope{actor: user, tenant: user.organization_id}

      first_blob = create_blob!(scope, "first avatar", "avatar-1.txt")

      assert {:ok, user} =
               Core.update_user_avatar(user, %{avatar_blob_id: first_blob.id}, scope: scope)

      assert user.avatar_blob_id == first_blob.id

      second_blob = create_blob!(scope, "second avatar", "avatar-2.txt")

      assert {:ok, updated_user} =
               Core.update_user_avatar(user, %{avatar_blob_id: second_blob.id}, scope: scope)

      assert updated_user.avatar_blob_id == second_blob.id

      assert_raise Ash.Error.Invalid, fn ->
        Blobs.get_blob!(first_blob.id, scope: scope)
      end

      assert Blobs.get_blob!(second_blob.id, scope: scope).id == second_blob.id
    end
  end

  defp create_blob!(scope, content, filename) do
    {:ok, path} = Briefly.create()
    File.write!(path, content)

    assert {:ok, blob} = Blobs.create_blob(path, "text/plain", filename, scope: scope)
    blob
  end
end
