defmodule Firmowid.Repo.Migrations.AddGoogleProviderIdToUsersTokens do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :google_provider_id, :string
    end
  end
end
