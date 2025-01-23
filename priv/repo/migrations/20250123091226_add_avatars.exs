defmodule Firmowid.Repo.Migrations.AddUserAvatar do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_blob_id, references(:blobs, on_delete: :nilify_all)
    end

    alter table(:organizations) do
      add :avatar_blob_id, references(:blobs, on_delete: :nilify_all)
    end
  end
end
