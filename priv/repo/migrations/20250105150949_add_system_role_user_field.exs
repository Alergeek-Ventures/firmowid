defmodule Firmowid.Repo.Migrations.AddSystemRoleUserField do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :system_role, :string, default: "user"
    end
  end
end
