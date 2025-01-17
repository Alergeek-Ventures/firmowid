defmodule Firmowid.Repo.Migrations.AddDefaultBankAccounts do
  use Ecto.Migration

  def change do
    alter table(:bank_accounts) do
      add :is_default, :boolean, default: false, null: false
    end

    create unique_index(
             :bank_accounts,
             [:organization_id, :currency, :is_default],
             where: "is_default = true"
           )
  end
end
