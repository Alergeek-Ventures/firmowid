defmodule Firmowid.Repo.Migrations.AddGoogleProviderIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_provider_id, :string
    end

    # Ensure unique Google accounts (only when google_provider_id is set)
    create unique_index(:users, [:google_provider_id], where: "google_provider_id IS NOT NULL")
  end
end
