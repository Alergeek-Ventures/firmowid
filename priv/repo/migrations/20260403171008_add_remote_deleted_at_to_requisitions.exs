defmodule Firmowid.Repo.Migrations.AddRemoteDeletedAtToRequisitions do
  use Ecto.Migration

  def change do
    alter table(:requisitions) do
      add :remote_deleted_at, :utc_datetime
    end
  end
end
