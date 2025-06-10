defmodule Firmowid.Repo.Migrations.CreateUserSalaries do
  use Ecto.Migration

  def change do
    create table(:user_salaries) do
      add :hourly_rate, :decimal, precision: 10, scale: 2, null: false
      add :effective_from, :date, null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:user_salaries, [:user_id])
    create index(:user_salaries, [:organization_id])
    create unique_index(:user_salaries, [:user_id, :effective_from, :organization_id])
  end
end
