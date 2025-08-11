defmodule Firmowid.Repo.Migrations.MakeRequisitionNullableInBankAccounts do
  use Ecto.Migration

  def change do
    alter table(:bank_accounts) do
      modify :requisition_id, :uuid, null: true
    end
  end
end
