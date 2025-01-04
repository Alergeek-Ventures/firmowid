defmodule Firmowid.Repo.Migrations.AddGocardlessIdToBankAccounts do
  use Ecto.Migration

  def change do
    alter table(:bank_accounts) do
      add :gocardless_id, :string, default: nil
    end
  end
end
