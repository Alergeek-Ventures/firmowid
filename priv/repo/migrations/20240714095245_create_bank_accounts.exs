defmodule Firmowid.Repo.Migrations.CreateBankAccounts do
  use Ecto.Migration

  def change do
    create table(:bank_accounts) do
      add :iban, :string

      timestamps(type: :utc_datetime)
    end
  end
end
