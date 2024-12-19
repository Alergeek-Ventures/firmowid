defmodule Firmowid.Repo.Migrations.AddPeselToBuyer do
  use Ecto.Migration

  def change do
    alter table(:buyers) do
      add :pesel, :string
    end

    alter table(:invoices) do
      add :buyer_pesel, :string
    end
  end
end
