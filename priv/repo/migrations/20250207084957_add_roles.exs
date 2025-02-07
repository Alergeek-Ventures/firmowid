defmodule Firmowid.Repo.Migrations.AddRoles do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, default: "employee"
    end
  end
end
