defmodule Firmowid.Repo.Migrations.RenameEffectiveFromToDeletedAt do
  use Ecto.Migration

  def change do
    drop unique_index(:user_salaries, [:user_id, :effective_from, :organization_id])

    rename table(:user_salaries), :effective_from, to: :deleted_at

    alter table(:user_salaries) do
      modify :deleted_at, :date, null: true
    end

    # Only one active (NULL deleted_at) salary per user per organization
    create unique_index(:user_salaries, [:user_id, :organization_id],
             where: "deleted_at IS NULL",
             name: :user_salaries_active_unique_index
           )
  end
end
