defmodule Firmowid.Repo.Migrations.AddBankTransferFieldExtraction do
  use Ecto.Migration

  def change do
    # now we extract account number and seller address specifically,
    # to later display when user wants these details to complete a
    # bank transfer

    alter table(:cost_invoices) do
      add :account_number, :string, null: true
      add :seller_address, :string, null: true
    end
  end
end
