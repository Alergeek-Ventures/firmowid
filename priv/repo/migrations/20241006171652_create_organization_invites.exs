defmodule Firmowid.Repo.Migrations.CreateOrganizationInvites do
  use Ecto.Migration

  def change do
    create table(:organization_invites) do
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime

      add :invite_code, :string, null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      add :issued_by_id, references(:users, on_delete: :delete_all), null: false

      add :consumed_by_id, references(:users, on_delete: :delete_all)

      timestamps()
    end
  end
end
