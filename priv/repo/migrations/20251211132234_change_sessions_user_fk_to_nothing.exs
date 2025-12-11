defmodule Firmowid.Repo.Migrations.ChangeSessionsUserFkToNothing do
  use Ecto.Migration

  def change do
    drop constraint(:sessions, :sessions_user_id_fkey)

    alter table(:sessions) do
      modify :user_id, references(:users, on_delete: :nothing), null: false
    end
  end
end
