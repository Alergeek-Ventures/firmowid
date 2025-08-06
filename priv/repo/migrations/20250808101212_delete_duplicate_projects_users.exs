defmodule Firmowid.Repo.Migrations.DeleteDuplicateProjectsUsers do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM projects_users
    WHERE id IN (
      SELECT id
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY project_id, user_id
               ORDER BY inserted_at ASC) AS rn
        FROM projects_users) t
        WHERE rn > 1
    )
    """

    create unique_index(:projects_users, [:project_id, :user_id])
  end

  def down do
    drop unique_index(:projects_users, [:project_id, :user_id])
  end
end
